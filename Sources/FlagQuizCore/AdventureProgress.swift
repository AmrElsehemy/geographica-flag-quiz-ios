import Foundation
import GameTimeCore
import GeographicaCore

/// Everything the player has earned. Plain `Codable` so any store can persist it.
public struct AdventureProgress: Codable, Equatable, Sendable {
    public private(set) var starsByStop: [String: Int] = [:]
    public private(set) var lastDailyKey: String?
    /// The streak as of `lastDailyKey`. Show `displayedDailyStreak(on:)` instead, which drops to 0 once
    /// the streak has been broken.
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

    /// A missed day ends the streak.
    public static let streakPolicy: DailyStreak.MissPolicy = .reset

    /// The saved streak as GameTimeKit's `DailyStreak`. The save format stays `lastDailyKey` plus
    /// `dailyStreak`, so existing progress carries over unchanged.
    private var streak: DailyStreak {
        DailyStreak(current: dailyStreak, lastCompletedDay: lastDailyKey.flatMap(DailyDay.init(key:)))
    }

    /// The streak to show on the UTC day containing `date`: the saved count while today's or
    /// yesterday's daily was played, 0 once a day has been missed.
    public func displayedDailyStreak(on date: Date) -> Int {
        streak.displayed(today: DailyChallenge.day(for: date), policy: Self.streakPolicy)
    }

    /// Records the **first** daily attempt of a UTC day: it sets that day's score and extends or
    /// resets the streak. Later attempts the same day are practice and change nothing, so a daily
    /// result can't be farmed by replaying a known question set; nor do attempts on an earlier day
    /// than the last counted one (a device clock set back).
    /// Returns whether this attempt counted.
    @discardableResult
    public mutating func recordDaily(score: Int, on date: Date) -> Bool {
        let day = DailyChallenge.day(for: date)
        var updated = streak
        guard updated.recordCompletion(on: day, policy: Self.streakPolicy) else { return false }
        dailyStreak = updated.current
        lastDailyKey = day.key
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
