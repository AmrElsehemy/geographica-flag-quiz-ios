import Foundation
import GameTimePersistence
import Testing
@testable import FlagQuizCore

@Suite struct PersistenceTests {
    private func defaults() -> (UserDefaults, String) {
        let suite = "flagquiz.persistence.tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func progressSavedByThePreviousBuildStillLoads() throws {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        // Exactly what the previous UserDefaultsProgressStore wrote: plain JSONEncoder output.
        let saved = Data(#"{"starsByStop":{"europe-1":3},"lastDailyKey":"2026-10-11","dailyStreak":4,"bestDailyScore":820,"lastDailyScore":610}"#.utf8)
        d.set(saved, forKey: "flagquiz.progress.v1")

        let store = UserDefaultsProgressStore(defaults: d)
        let progress = store.load()
        #expect(progress.starsByStop == ["europe-1": 3])
        #expect(progress.dailyStreak == 4 && progress.bestDailyScore == 820)
        #expect(store.lastRecovery == nil)
    }

    @Test func anUnreadableSaveIsBackedUpInsteadOfOverwritten() throws {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        let corrupted = Data("{\"starsByStop\": 3".utf8)
        d.set(corrupted, forKey: "flagquiz.progress.v1")

        let store = UserDefaultsProgressStore(defaults: d)
        #expect(store.load() == AdventureProgress(), "The player starts fresh...")
        let recovery = try #require(store.lastRecovery, "...and the store says why")

        var progress = AdventureProgress()
        progress.recordDaily(score: 500, on: Date())
        store.save(progress)

        // The previous store would have overwritten the unreadable bytes here; they are kept instead.
        let backups = SaveStore<AdventureProgress>(key: "flagquiz.progress.v1", codec: .json, defaults: d) { AdventureProgress() }
        #expect(backups.backups() == [recovery])
        #expect(backups.backupData(for: recovery) == corrupted)
        #expect(UserDefaultsProgressStore(defaults: d).load().bestDailyScore == 500)

        _ = store.load()
        #expect(store.lastRecovery == nil, "A later successful load clears the recovery")
    }

    @Test func onboardingAndScoreQueueKeepTheirKeysAndRecoverToo() {
        let (d, suite) = defaults(); defer { d.removePersistentDomain(forName: suite) }
        var onboarding = OnboardingProgress()
        onboarding.completeTutorial()
        UserDefaultsOnboardingStore(defaults: d).save(onboarding)
        #expect(d.data(forKey: "flagquiz.onboarding.v1") != nil)
        #expect(UserDefaultsOnboardingStore(defaults: d).load() == onboarding)

        d.set(Data("nope".utf8), forKey: "flagquiz.scorequeue.v1")
        let queue = UserDefaultsScoreQueueStore(defaults: d)
        #expect(queue.load() == ScoreQueue())
        #expect(queue.lastRecovery != nil)
    }
}
