import Foundation
import GeographicaCore

/// Everything the player has earned. Plain `Codable` so any store can persist it.
public struct AdventureProgress: Codable, Equatable, Sendable {
    public private(set) var starsByStop: [String: Int] = [:]
    public private(set) var lastDailyKey: String?
    public private(set) var dailyStreak = 0
    public private(set) var bestDailyScore = 0
    /// Score of the counting (first) attempt on `lastDailyKey`.
    public private(set) var lastDailyScore: Int?

    public init() {}

    public var totalStars: Int { starsByStop.values.reduce(0, +) }

    public func stars(for stop: Stop) -> Int { starsByStop[stop.id] ?? 0 }

    public func stars(in chapter: Chapter) -> Int {
        chapter.stops.reduce(0) { $0 + stars(for: $1) }
    }

    /// Keeps the best result per stop.
    public mutating func record(stars: Int, for stop: Stop) {
        let clamped = min(max(stars, 0), Adventure.maxStarsPerStop)
        starsByStop[stop.id] = max(starsByStop[stop.id] ?? 0, clamped)
    }

    public func isChapterUnlocked(_ chapter: Chapter) -> Bool {
        guard let index = Adventure.chapters.firstIndex(of: chapter), index > 0 else { return true }
        let previous = Adventure.chapters[index - 1]
        return stars(in: previous) >= Adventure.starsToUnlockNext(after: previous)
    }

    public func isStopUnlocked(_ stop: Stop) -> Bool {
        guard let chapter = Adventure.chapter(for: stop.continent), isChapterUnlocked(chapter) else { return false }
        guard stop.number > 1 else { return true }
        return stars(for: chapter.stops[stop.number - 2]) >= 1
    }

    public func hasPlayedDaily(on key: String) -> Bool { lastDailyKey == key }

    /// The counting score for the UTC day containing `date`, if that day's attempt has been used.
    public func dailyScore(on date: Date) -> Int? {
        lastDailyKey == DailyChallenge.dayKey(for: date) ? lastDailyScore : nil
    }

    /// Records the **first** daily attempt of a UTC day: it sets that day's score and extends or
    /// resets the streak. Later attempts the same day are practice and change nothing, so a daily
    /// result can't be farmed by replaying a known question set.
    /// Returns whether this attempt counted.
    @discardableResult
    public mutating func recordDaily(score: Int, on date: Date) -> Bool {
        let key = DailyChallenge.dayKey(for: date)
        guard lastDailyKey != key else { return false }
        let yesterday = DailyChallenge.calendar.date(byAdding: .day, value: -1, to: date)
            .map { DailyChallenge.dayKey(for: $0) }
        dailyStreak = (lastDailyKey != nil && lastDailyKey == yesterday) ? dailyStreak + 1 : 1
        lastDailyKey = key
        lastDailyScore = score
        bestDailyScore = max(bestDailyScore, score)
        return true
    }
}

public protocol ProgressStoring: Sendable {
    func load() -> AdventureProgress
    func save(_ progress: AdventureProgress)
}

public final class InMemoryProgressStore: ProgressStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var progress = AdventureProgress()

    public init() {}

    public func load() -> AdventureProgress { lock.withLock { progress } }
    public func save(_ progress: AdventureProgress) { lock.withLock { self.progress = progress } }
}

public final class UserDefaultsProgressStore: ProgressStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "flagquiz.progress.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AdventureProgress {
        guard let data = defaults.data(forKey: key),
              let progress = try? JSONDecoder().decode(AdventureProgress.self, from: data)
        else { return AdventureProgress() }
        return progress
    }

    public func save(_ progress: AdventureProgress) {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: key) }
    }
}
