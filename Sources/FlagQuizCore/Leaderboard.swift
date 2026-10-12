import Foundation

/// The Game Center leaderboard for the Daily Challenge.
public enum Leaderboard {
    /// Must match the **Leaderboard ID** of the recurring leaderboard in App Store Connect exactly.
    public static let dailyID = "ai.knowlly.flagquiz.daily"
}

public enum ScoreSubmissionError: Error, Equatable, Sendable {
    /// Game Center has no signed-in player right now.
    case notAuthenticated
}

/// The thing that actually delivers a score (GameKit in the app, a fake in tests).
public protocol ScoreSubmitting: Sendable {
    func submit(score: Int, leaderboardID: String) async throws
}

/// A daily score waiting to be delivered.
public struct PendingScore: Codable, Equatable, Sendable {
    /// UTC day (`yyyy-MM-dd`) the score was earned on.
    public let dayKey: String
    public let score: Int
}

/// Scores that couldn't be delivered yet (offline, not signed in). Plain `Codable` so it persists.
///
/// A daily leaderboard is recurring: a score submitted today lands on **today's** board. So a queued
/// score is only ever delivered on the UTC day it was earned, and is dropped afterwards, otherwise
/// yesterday's score would appear on today's board.
public struct ScoreQueue: Codable, Equatable, Sendable {
    public private(set) var items: [PendingScore] = []
    /// The most recent day whose score reached Game Center. Remembered so a second score for a day
    /// that was already delivered can never be queued (the first attempt is the one that counts).
    public private(set) var lastDeliveredDayKey: String?

    public init() {}

    /// One score per day: the first attempt counts, so a second enqueue for the same day is ignored,
    /// whether the first is still waiting or has already been delivered.
    public mutating func enqueue(dayKey: String, score: Int) {
        guard dayKey != lastDeliveredDayKey, !items.contains(where: { $0.dayKey == dayKey }) else { return }
        items.append(PendingScore(dayKey: dayKey, score: score))
    }

    public func due(today: String) -> [PendingScore] {
        items.filter { $0.dayKey == today }
    }

    public mutating func complete(dayKey: String) {
        items.removeAll { $0.dayKey == dayKey }
        lastDeliveredDayKey = dayKey
    }

    public mutating func discardExpired(today: String) {
        items.removeAll { $0.dayKey != today }
    }
}

public protocol ScoreQueueStoring: Sendable {
    func load() -> ScoreQueue
    func save(_ queue: ScoreQueue)
}

public final class InMemoryScoreQueueStore: ScoreQueueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var queue = ScoreQueue()

    public init() {}

    public func load() -> ScoreQueue { lock.withLock { queue } }
    public func save(_ queue: ScoreQueue) { lock.withLock { self.queue = queue } }
}

public final class UserDefaultsScoreQueueStore: ScoreQueueStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "flagquiz.scorequeue.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ScoreQueue {
        guard let data = defaults.data(forKey: key),
              let queue = try? JSONDecoder().decode(ScoreQueue.self, from: data)
        else { return ScoreQueue() }
        return queue
    }

    public func save(_ queue: ScoreQueue) {
        if let data = try? JSONEncoder().encode(queue) { defaults.set(data, forKey: key) }
    }
}

public enum SubmitOutcome: Equatable, Sendable {
    /// The score is on the leaderboard.
    case submitted
    /// The score is saved and will be delivered later the same day (offline, not signed in, or failed).
    case queued
    /// There was nothing to deliver (no score for today, or the score's day has ended).
    case nothingToSubmit
}

/// Delivers the daily score reliably: queue first, then try to send, and retry later if that fails.
/// An actor, so two triggers (finishing a run and Game Center signing in) can't deliver the same
/// score twice.
public actor LeaderboardSubmitter {
    private let submitter: any ScoreSubmitting
    private let store: any ScoreQueueStoring
    private let now: @Sendable () -> Date

    public init(submitter: any ScoreSubmitting,
                store: any ScoreQueueStoring,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.submitter = submitter
        self.store = store
        self.now = now
    }

    /// Records a counting daily score earned at `date` and tries to deliver it straight away.
    public func record(score: Int, on date: Date) async -> SubmitOutcome {
        var queue = store.load()
        queue.enqueue(dayKey: DailyChallenge.dayKey(for: date), score: score)
        store.save(queue)
        return await flush()
    }

    /// Delivers whatever is waiting for today's board. Call on launch, on foreground and after
    /// Game Center signs in.
    @discardableResult
    public func flush() async -> SubmitOutcome {
        let today = DailyChallenge.dayKey(for: now())
        var queue = store.load()
        queue.discardExpired(today: today)
        store.save(queue)

        let due = queue.due(today: today)
        guard !due.isEmpty else { return .nothingToSubmit }

        var outcome = SubmitOutcome.submitted
        for pending in due {
            do {
                try await submitter.submit(score: pending.score, leaderboardID: Leaderboard.dailyID)
                queue.complete(dayKey: pending.dayKey)
                store.save(queue)
            } catch {
                outcome = .queued
            }
        }
        return outcome
    }

    public func pendingCount() -> Int { store.load().items.count }
}
