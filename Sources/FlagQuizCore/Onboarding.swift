import Foundation

/// One-time hints shown in context, never as a wall of instructions.
public enum Hint: String, Codable, CaseIterable, Sendable {
    /// On the map after the tutorial: "tap stop 1".
    case mapStart
    /// On the first completed stop: how stars work.
    case stars
    /// On the map after the first star: the Daily Challenge exists.
    case daily
}

/// What the player has been taught. Separate from `AdventureProgress` so each can evolve on its own.
public struct OnboardingProgress: Codable, Equatable, Sendable {
    public private(set) var tutorialCompleted = false
    public private(set) var tutorialSkipped = false
    public private(set) var seenHints: Set<Hint> = []

    public init() {}

    /// First launch: play the tutorial unless it was finished or skipped before.
    public var shouldShowTutorial: Bool { !tutorialCompleted && !tutorialSkipped }

    public func hasSeen(_ hint: Hint) -> Bool { seenHints.contains(hint) }

    public mutating func completeTutorial() { tutorialCompleted = true }
    public mutating func skipTutorial() { tutorialSkipped = true }
    public mutating func markSeen(_ hint: Hint) { seenHints.insert(hint) }

    /// The hint to show on the map right now, if any. At most one at a time, and never during the
    /// tutorial.
    public func mapHint(progress: AdventureProgress) -> Hint? {
        guard !shouldShowTutorial else { return nil }
        if !hasSeen(.mapStart), progress.totalStars == 0 { return .mapStart }
        if !hasSeen(.daily), progress.totalStars >= 1, progress.lastDailyKey == nil { return .daily }
        return nil
    }
}

public protocol OnboardingStoring: Sendable {
    func load() -> OnboardingProgress
    func save(_ progress: OnboardingProgress)
}

public final class InMemoryOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var progress = OnboardingProgress()

    public init() {}

    public func load() -> OnboardingProgress { lock.withLock { progress } }
    public func save(_ progress: OnboardingProgress) { lock.withLock { self.progress = progress } }
}

public final class UserDefaultsOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "flagquiz.onboarding.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> OnboardingProgress {
        guard let data = defaults.data(forKey: key),
              let progress = try? JSONDecoder().decode(OnboardingProgress.self, from: data)
        else { return OnboardingProgress() }
        return progress
    }

    public func save(_ progress: OnboardingProgress) {
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: key) }
    }
}
