import FlagQuizCore
import Foundation
import GameTimeExperience
import Observation

@MainActor
@Observable
final class AppModel {
    private(set) var progress: AdventureProgress
    private(set) var soundEnabled: Bool
    private(set) var hapticsEnabled: Bool

    @ObservationIgnored private let store: any ProgressStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let feedback: GameFeedbackController
    @ObservationIgnored let ads = AdService()

    private enum Keys {
        static let sound = "flagquiz.sound"
        static let haptics = "flagquiz.haptics"
    }

    init(store: any ProgressStoring = UserDefaultsProgressStore(), defaults: UserDefaults = .standard) {
        self.store = store
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

    func prepareAds() async { await ads.prepare() }

    func requestRefuel(attemptID: String, refuelNumber: Int) async -> RefuelOutcome {
        await ads.requestRefuel(attemptID: attemptID, refuelNumber: refuelNumber,
                                completedStops: progress.starsByStop.count)
    }

    func finish(stop: Stop, stars: Int) {
        progress.record(stars: stars, for: stop)
        store.save(progress)
    }

    func finishDaily(score: Int, on date: Date = Date()) {
        progress.recordDaily(score: score, on: date)
        store.save(progress)
    }
}
