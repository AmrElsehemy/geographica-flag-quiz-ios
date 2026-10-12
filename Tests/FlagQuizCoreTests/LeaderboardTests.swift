import Foundation
import GameTimeServices
import GameTimeTesting
import Testing
@testable import FlagQuizCore

/// A scriptable stand-in for Game Center.
private actor FakeScoreSubmitter: ScoreSubmitting {
    private(set) var delivered: [(score: Int, id: String)] = []
    private var failures: [Error]

    init(failures: [Error] = []) { self.failures = failures }

    func submit(score: Int, leaderboardID: String) async throws {
        if !failures.isEmpty { throw failures.removeFirst() }
        delivered.append((score, leaderboardID))
    }

    func setFailures(_ errors: [Error]) { failures = errors }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date) { current = date }
    var now: Date { lock.withLock { current } }
    func set(_ date: Date) { lock.withLock { current = date } }
}

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    DailyChallenge.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private struct Harness {
    let fake: FakeScoreSubmitter
    let store = InMemoryScoreQueueStore()
    let clock: MutableClock
    let submitter: LeaderboardSubmitter

    init(failures: [Error] = [], start: Date = utc(2026, 10, 10)) {
        fake = FakeScoreSubmitter(failures: failures)
        clock = MutableClock(start)
        let clock = self.clock
        submitter = LeaderboardSubmitter(submitter: fake, store: store, now: { clock.now })
    }
}

@Suite struct ScoreQueueTests {
    @Test func aDeliveredDayCannotBeQueuedAgain() {
        var q = ScoreQueue()
        q.enqueue(dayKey: "2026-10-10", score: 400)
        q.complete(dayKey: "2026-10-10")
        q.enqueue(dayKey: "2026-10-10", score: 900)
        #expect(q.items.isEmpty)
        #expect(q.lastDeliveredDayKey == "2026-10-10")
        q.enqueue(dayKey: "2026-10-11", score: 500)
        #expect(q.items.map(\.score) == [500])
    }

    @Test func oldSavedQueuesWithoutTheNewFieldStillLoad() throws {
        let legacy = Data(#"{"items":[{"dayKey":"2026-10-10","score":400}]}"#.utf8)
        let q = try JSONDecoder().decode(ScoreQueue.self, from: legacy)
        #expect(q.items.count == 1 && q.lastDeliveredDayKey == nil)
    }

    @Test func onlyTheFirstScoreOfADayIsKept() {
        var q = ScoreQueue()
        q.enqueue(dayKey: "2026-10-10", score: 400)
        q.enqueue(dayKey: "2026-10-10", score: 900)
        #expect(q.items == [PendingScore(dayKey: "2026-10-10", score: 400)])
    }

    @Test func dueIsOnlyTodaysScore() {
        var q = ScoreQueue()
        q.enqueue(dayKey: "2026-10-09", score: 300)
        q.enqueue(dayKey: "2026-10-10", score: 400)
        #expect(q.due(today: "2026-10-10").map(\.score) == [400])
    }

    @Test func expiredScoresAreDropped() {
        var q = ScoreQueue()
        q.enqueue(dayKey: "2026-10-09", score: 300)
        q.enqueue(dayKey: "2026-10-10", score: 400)
        q.discardExpired(today: "2026-10-10")
        #expect(q.items.map(\.dayKey) == ["2026-10-10"])
    }

    @Test func roundTripsThroughJSONAndStores() throws {
        var q = ScoreQueue()
        q.enqueue(dayKey: "2026-10-10", score: 640)
        let decoded = try JSONDecoder().decode(ScoreQueue.self, from: JSONEncoder().encode(q))
        #expect(decoded == q)
        let memory = InMemoryScoreQueueStore()
        memory.save(q)
        #expect(memory.load() == q)
        let defaults = try #require(UserDefaults(suiteName: "queue-tests-\(UUID().uuidString)"))
        let persisted = UserDefaultsScoreQueueStore(defaults: defaults)
        #expect(persisted.load().items.isEmpty)
        persisted.save(q)
        #expect(persisted.load() == q)
    }
}

@Suite struct LeaderboardSubmitterTests {
    @Test func deliversAScoreImmediatelyWhenGameCenterIsAvailable() async {
        let h = Harness()
        let outcome = await h.submitter.record(score: 640, on: utc(2026, 10, 10))
        #expect(outcome == .submitted)
        let delivered = await h.fake.delivered
        #expect(delivered.count == 1 && delivered[0].score == 640 && delivered[0].id == Leaderboard.dailyID)
        #expect(await h.submitter.pendingCount() == 0)
    }

    @Test func keepsTheScoreWhenDeliveryFailsAndRetriesLater() async {
        let h = Harness(failures: [ScoreSubmissionError.notAuthenticated])
        let first = await h.submitter.record(score: 640, on: utc(2026, 10, 10))
        #expect(first == .queued)
        #expect(await h.submitter.pendingCount() == 1)

        // Game Center signs in later the same day.
        let retry = await h.submitter.flush()
        #expect(retry == .submitted)
        #expect(await h.fake.delivered.map(\.score) == [640])
        #expect(await h.submitter.pendingCount() == 0)
    }

    @Test func aSecondScoreForAnAlreadyDeliveredDayIsIgnored() async {
        let h = Harness()
        #expect(await h.submitter.record(score: 640, on: utc(2026, 10, 10)) == .submitted)
        // Repeated flushes and a second same-day score (e.g. a bug upstream) must not post again.
        _ = await h.submitter.flush()
        #expect(await h.submitter.record(score: 999, on: utc(2026, 10, 10)) == .nothingToSubmit)
        #expect(await h.fake.delivered.map(\.score) == [640])
    }

    @Test func aScoreFromYesterdayIsDroppedNotPostedToTodaysBoard() async {
        let h = Harness(failures: [ScoreSubmissionError.notAuthenticated])
        _ = await h.submitter.record(score: 640, on: utc(2026, 10, 10))   // fails, queued
        h.clock.set(utc(2026, 10, 11, 0))                                  // the next UTC day
        let outcome = await h.submitter.flush()
        #expect(outcome == .nothingToSubmit)
        #expect(await h.fake.delivered.isEmpty)
        #expect(await h.submitter.pendingCount() == 0)
    }

    @Test func aRunThatFinishesAfterMidnightStillBelongsToTheDayItStartedOn() async {
        // Started on the 10th, recorded with the 10th's date, but "now" is already the 11th.
        let h = Harness(start: utc(2026, 10, 11, 0))
        let outcome = await h.submitter.record(score: 500, on: utc(2026, 10, 10, 23))
        #expect(outcome == .nothingToSubmit)
        #expect(await h.fake.delivered.isEmpty)
    }

    @Test func newDayNewScore() async {
        let h = Harness()
        _ = await h.submitter.record(score: 640, on: utc(2026, 10, 10))
        h.clock.set(utc(2026, 10, 11))
        let outcome = await h.submitter.record(score: 720, on: utc(2026, 10, 11))
        #expect(outcome == .submitted)
        #expect(await h.fake.delivered.map(\.score) == [640, 720])
    }

    @Test func partialFailureReportsQueued() async {
        let h = Harness(failures: [URLError(.notConnectedToInternet)])
        #expect(await h.submitter.record(score: 640, on: utc(2026, 10, 10)) == .queued)
        #expect(await h.submitter.flush() == .submitted)
    }
}

@Suite struct LeaderboardAnalyticsTests {
    @Test func reportsSubmittedAndQueuedButNotNothing() {
        let client = RecordingAnalyticsClient()
        let analytics = FlagQuizAnalytics(client: client)
        analytics.leaderboardSubmit(.submitted)
        analytics.leaderboardSubmit(.queued)
        analytics.leaderboardSubmit(.nothingToSubmit)
        #expect(client.events.map(\.name) == ["leaderboard_submit", "leaderboard_submit"])
        #expect(client.events.map { $0.properties["status"] } == ["submitted", "queued"])
    }

    @Test func leaderboardIDIsStable() {
        #expect(Leaderboard.dailyID == "ai.knowlly.flagquiz.daily")
    }
}
