import FlagQuizCore
import Foundation
import GameTimeAnalytics
import GameTimeExperience
import GameTimePersistence
import GameTimeServices
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var progress: AdventureProgress
    private(set) var onboarding: OnboardingProgress
    private(set) var soundEnabled: Bool
    private(set) var hapticsEnabled: Bool
    /// Whether anonymous usage data is sent. On by default; the player can turn it off in Settings.
    private(set) var analyticsSharing: Bool

    @ObservationIgnored private let store: any ProgressStoring
    @ObservationIgnored private let onboardingStore: any OnboardingStoring
    /// Sound and haptics, under the keys earlier builds used, so players' choices carry over.
    @ObservationIgnored private let settings: FeedbackSettingsStore
    @ObservationIgnored private let feedback: GameFeedbackController
    @ObservationIgnored let ads = AdService()
    @ObservationIgnored let analytics: FlagQuizAnalytics
    /// Nil in demo mode, which records nothing.
    @ObservationIgnored private let analyticsPipeline: AnalyticsPipeline?
    @ObservationIgnored private let adsEnabled: Bool
    @ObservationIgnored private let gameCenterEnabled: Bool
    @ObservationIgnored let gameCenter = GameCenterService()
    @ObservationIgnored private let leaderboard: LeaderboardSubmitter
    /// How the latest counting daily score fared with the leaderboard (nil until one is recorded).
    private(set) var dailyLeaderboardStatus: SubmitOutcome?
    /// A run to present at launch (debug demo mode only, used for screenshots).
    private(set) var demoRun: Run?

    init(store: any ProgressStoring = UserDefaultsProgressStore(),
         onboardingStore: any OnboardingStoring = UserDefaultsOnboardingStore(),
         defaults: UserDefaults = .standard,
         analyticsPipeline: AnalyticsPipeline? = FlagTrekAnalytics.makePipeline(),
         adsEnabled: Bool = true,
         gameCenterEnabled: Bool = true,
         scoreSubmitter: any ScoreSubmitting = GameKitScoreSubmitter(),
         scoreQueueStore: any ScoreQueueStoring = UserDefaultsScoreQueueStore()) {
        self.adsEnabled = adsEnabled
        self.gameCenterEnabled = gameCenterEnabled
        self.leaderboard = LeaderboardSubmitter(submitter: scoreSubmitter, store: scoreQueueStore)
        self.analyticsPipeline = analyticsPipeline
        self.analytics = FlagQuizAnalytics(client: analyticsPipeline ?? NoOpAnalyticsClient())
        self.analyticsSharing = analyticsPipeline?.isSharingEnabled ?? false
        self.store = store
        self.onboardingStore = onboardingStore
        self.onboarding = onboardingStore.load()
        self.progress = store.load()
        let settings = FeedbackSettingsStore(soundKey: "flagquiz.sound", hapticsKey: "flagquiz.haptics", defaults: defaults)
        self.settings = settings
        self.soundEnabled = settings.current.soundEnabled
        self.hapticsEnabled = settings.current.hapticsEnabled
        self.feedback = FlagQuizFeedback.makeController()
        // A save that could not be read was backed up rather than lost; count how often that happens.
        if (store as? RecoveryReporting)?.lastRecovery != nil { analytics.saveRecovered(store: "progress") }
        if (onboardingStore as? RecoveryReporting)?.lastRecovery != nil { analytics.saveRecovered(store: "onboarding") }
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        settings.setSoundEnabled(enabled)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        settings.setHapticsEnabled(enabled)
    }

    func setAnalyticsSharing(_ enabled: Bool) {
        analyticsPipeline?.setSharingEnabled(enabled)
        analyticsSharing = enabled
    }

    /// Counts a finished stop or daily toward the current session's `session_end.levels_completed`.
    func noteLevelCompleted() { analyticsPipeline?.noteLevelCompleted() }

    func play(_ event: GameFeedbackEvent) {
        feedback.play(event, soundEnabled: soundEnabled, hapticsEnabled: hapticsEnabled)
    }

    func appBecameActive() {
        analyticsPipeline?.appDidBecomeActive()
        if gameCenter.isAuthenticated { flushLeaderboard() }
    }
    func appWentToBackground() { analyticsPipeline?.appDidEnterBackground() }

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
