import FlagQuizCore
import Foundation
import GameTimeExperience
import GameTimeServices
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var progress: AdventureProgress
    private(set) var onboarding: OnboardingProgress
    private(set) var soundEnabled: Bool
    private(set) var hapticsEnabled: Bool

    @ObservationIgnored private let store: any ProgressStoring
    @ObservationIgnored private let onboardingStore: any OnboardingStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let feedback: GameFeedbackController
    @ObservationIgnored let ads = AdService()
    @ObservationIgnored let analytics: FlagQuizAnalytics
    @ObservationIgnored private var appSession: SessionAnalytics
    @ObservationIgnored private let adsEnabled: Bool
    @ObservationIgnored private let gameCenterEnabled: Bool
    @ObservationIgnored let gameCenter = GameCenterService()
    @ObservationIgnored private let leaderboard: LeaderboardSubmitter
    /// How the latest counting daily score fared with the leaderboard (nil until one is recorded).
    private(set) var dailyLeaderboardStatus: SubmitOutcome?
    /// A run to present at launch (debug demo mode only, used for screenshots).
    private(set) var demoRun: Run?

    private enum Keys {
        static let sound = "flagquiz.sound"
        static let haptics = "flagquiz.haptics"
    }

    init(store: any ProgressStoring = UserDefaultsProgressStore(),
         onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore(),
         defaults: UserDefaults = .standard,
         analyticsClient: any AnalyticsClient = LoggingAnalyticsClient(),
         adsEnabled: Bool = true,
         gameCenterEnabled: Bool = true,
         scoreSubmitter: any ScoreSubmitting = GameKitScoreSubmitter(),
         scoreQueueStore: any ScoreQueueStoring = UserDefaultsScoreQueueStore()) {
        self.adsEnabled = adsEnabled
        self.gameCenterEnabled = gameCenterEnabled
        self.leaderboard = LeaderboardSubmitter(submitter: scoreSubmitter, store: scoreQueueStore)
        let analytics = FlagQuizAnalytics(client: analyticsClient)
        self.analytics = analytics
        self.appSession = analytics.makeSession()
        self.store = store
        self.onboardingStore = onboardingStore
        self.onboarding = onboardingStore.load()
        self.defaults = defaults
        self.progress = store.load()
        self.soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.feedback = FlagQuizFeedback.makeController()
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        defaults.set(enabled, forKey: Keys.sound)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        defaults.set(enabled, forKey: Keys.haptics)
    }

    func play(_ event: GameFeedbackEvent) {
        feedback.play(event, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
    }

    func appBecameActive() {
        appSession.becameActive()
        if gameCenter.isAuthenticated { flushLeaderboard() }
    }
    func appWentToBackground() { appSession.wentToBackground() }

    func completeTutorial() {
        onboarding.completeTutorial()
        onboardingStore.save(onboarding)
    }

    func skipTutorial() {
        onboarding.skipTutorial()
        onboardingStore.save(onboarding)
    }

    /// Marks a one-time hint as seen (and reports it once).
    func markHintSeen(_ hint: Hint) {
        guard !onboarding.hasSeen(hint) else { return }
        onboarding.markSeen(hint)
        onboardingStore.save(onboarding)
        analytics.hintSeen(hint)
    }

    /// Whether running out of fuel offers a rewarded ad. False while the app ships without ads.
    var refuelOfferAvailable: Bool { adsEnabled && ads.isEnabled }

    func prepareAds() async {
        guard adsEnabled else { return }
        await ads.prepare()
    }

    func setDemoRun(_ run: Run?) { demoRun = run }

    func consumeDemoRun() -> Run? {
        defer { demoRun = nil }
        return demoRun
    }

    func requestRefuel(attemptID: String, refuelNumber: Int) async -> RefuelOutcome {
        await ads.requestRefuel(attemptID: attemptID, refuelNumber: refuelNumber,
                                completedStops: progress.starsByStop.count)
    }

    func finish(stop: Stop, stars: Int) {
        progress.record(stars: stars, for: stop)
        store.save(progress)
    }

    /// Starts Game Center sign-in. Called after the tutorial and the ad-consent form, so a new player
    /// isn't met by a stack of dialogs.
    func startGameCenter() {
        guard gameCenterEnabled else { return }
        gameCenter.onAuthenticated = { [weak self] in self?.flushLeaderboard() }
        gameCenter.start()
    }

    /// Delivers any score waiting for today's leaderboard.
    func flushLeaderboard() {
        Task {
            apply(await leaderboard.flush())
        }
    }

    private func apply(_ outcome: SubmitOutcome) {
        guard outcome != .nothingToSubmit else { return }
        dailyLeaderboardStatus = outcome
        analytics.leaderboardSubmit(outcome)
    }

    /// Records a finished daily run. Only the first attempt of a UTC day counts; that score is also
    /// sent to the Game Center leaderboard (queued and retried if it can't go out yet).
    func finishDaily(score: Int, on date: Date = Date()) {
        let counted = progress.recordDaily(score: score, on: date)
        store.save(progress)
        guard counted else { return }
        dailyLeaderboardStatus = nil
        Task {
            apply(await leaderboard.record(score: score, on: date))
        }
    }
}
