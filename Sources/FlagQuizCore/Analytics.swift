import Foundation
import GameTimeCore
import GameTimeServices
import GeographicaCore
import GeographicaFlags

/// What kind of run an event belongs to.
public enum RunMode: String, Sendable {
    case adventure
    /// The first daily attempt of a UTC day: counts toward the daily score and streak.
    case daily
    /// Any later attempt at the same day's set.
    case dailyPractice = "daily_practice"
}

/// Everything that identifies one attempt, repeated on each event so any event is analysable alone.
public struct RunContext: Equatable, Sendable {
    public let mode: RunMode
    public let levelID: String
    /// Unique per attempt (a retry is a new attempt of the same level).
    public let attemptID: String
    public let questionCount: Int
    public let chapter: String?
    public let stopNumber: Int?

    public init(mode: RunMode, levelID: String, attemptID: String, questionCount: Int,
                chapter: String? = nil, stopNumber: Int? = nil) {
        self.mode = mode
        self.levelID = levelID
        self.attemptID = attemptID
        self.questionCount = questionCount
        self.chapter = chapter
        self.stopNumber = stopNumber
    }

    public static func adventure(stop: Stop, session: QuizSession, attemptID: String) -> RunContext {
        RunContext(mode: .adventure, levelID: stop.id, attemptID: attemptID, questionCount: session.questions.count,
                   chapter: stop.continent.rawValue, stopNumber: stop.number)
    }

    public static func daily(counts: Bool, session: QuizSession, attemptID: String) -> RunContext {
        RunContext(mode: counts ? .daily : .dailyPractice, levelID: session.id, attemptID: attemptID,
                   questionCount: session.questions.count)
    }
}

/// Event names follow GameTimeKit's common vocabulary (see its ANALYTICS_AND_EXPERIMENTS doc). Bump
/// `schemaVersion` on any breaking change to a name or property so downstream queries stay valid.
public enum FlagQuizEvent {
    public static let schemaVersion = "1"
    public static let gameID = "flag_quiz"

    public static let sessionStart = "session_start"
    public static let sessionEnd = "session_end"
    public static let levelStarted = "level_started"
    public static let questionAnswered = "question_answered"
    public static let fuelExhausted = "fuel_exhausted"
    public static let levelCompleted = "level_completed"
    public static let levelFailed = "level_failed"
    public static let levelAbandoned = "level_abandoned"
    public static let rewardOfferShown = "reward_offer_shown"
    public static let rewardOfferAccepted = "reward_offer_accepted"
    public static let rewardOfferDeclined = "reward_offer_declined"
    public static let rewardCompleted = "reward_completed"
    public static let rewardFailed = "reward_failed"
    public static let dailyCompleted = "daily_completed"
    public static let tutorialStarted = "tutorial_started"
    public static let tutorialStep = "tutorial_step"
    public static let tutorialCompleted = "tutorial_completed"
    public static let tutorialSkipped = "tutorial_skipped"
    public static let hintSeen = "hint_seen"
}

/// Builds and sends events. Holds no player identity: events carry only gameplay facts and an
/// attempt id that is random per attempt.
public struct FlagQuizAnalytics: Sendable {
    private let client: any AnalyticsClient
    private let clock: any GameTimeClock

    public init(client: any AnalyticsClient, clock: any GameTimeClock = SystemGameTimeClock()) {
        self.client = client
        self.clock = clock
    }

    func send(_ name: String, _ properties: [String: String] = [:]) {
        var all = properties
        all["game"] = FlagQuizEvent.gameID
        all["schema"] = FlagQuizEvent.schemaVersion
        client.track(AnalyticsEvent(name: name, properties: all))
    }

    var now: Date { clock.now }

    public func makeRun(_ context: RunContext) -> RunAnalytics {
        RunAnalytics(context: context, analytics: self)
    }

    public func makeTutorial(replay: Bool) -> TutorialAnalytics {
        TutorialAnalytics(analytics: self, replay: replay)
    }

    /// A one-time hint was shown and dismissed or acted on.
    public func hintSeen(_ hint: Hint) {
        send(FlagQuizEvent.hintSeen, ["hint": hint.rawValue])
    }

    public func makeSession() -> SessionAnalytics {
        SessionAnalytics(analytics: self)
    }
}

/// Tracks one app session: `session_start` when the app becomes active, `session_end` (with duration)
/// when it goes to the background. Both calls are idempotent.
public struct SessionAnalytics: Sendable {
    private let analytics: FlagQuizAnalytics
    private var startedAt: Date?

    init(analytics: FlagQuizAnalytics) { self.analytics = analytics }

    public mutating func becameActive() {
        guard startedAt == nil else { return }
        startedAt = analytics.now
        analytics.send(FlagQuizEvent.sessionStart)
    }

    public mutating func wentToBackground() {
        guard let startedAt else { return }
        self.startedAt = nil
        analytics.send(FlagQuizEvent.sessionEnd, ["duration_s": seconds(analytics.now.timeIntervalSince(startedAt))])
    }
}

/// Tracks the tutorial funnel: `tutorial_started`, a `tutorial_step` per answer, then exactly one of
/// `tutorial_completed` or `tutorial_skipped`. Kept apart from `level_*` so practice answers never
/// pollute gameplay metrics.
public struct TutorialAnalytics: Sendable {
    private let analytics: FlagQuizAnalytics
    private let replay: Bool
    private var startedAt: Date
    private var finished = false

    init(analytics: FlagQuizAnalytics, replay: Bool) {
        self.analytics = analytics
        self.replay = replay
        self.startedAt = analytics.now
    }

    private func send(_ name: String, _ extra: [String: String] = [:]) {
        analytics.send(name, ["replay": replay ? "true" : "false"].merging(extra) { _, new in new })
    }

    public mutating func start() {
        startedAt = analytics.now
        send(FlagQuizEvent.tutorialStarted)
    }

    public func step(index: Int, correct: Bool) {
        send(FlagQuizEvent.tutorialStep, ["step": String(index), "correct": correct ? "true" : "false"])
    }

    public mutating func completed(session: QuizSession) {
        guard !finished else { return }
        finished = true
        send(FlagQuizEvent.tutorialCompleted, [
            "mistakes": String(session.mistakes),
            "duration_s": seconds(analytics.now.timeIntervalSince(startedAt))
        ])
    }

    /// `atStep` is how many questions were answered before the player skipped.
    public mutating func skipped(atStep: Int) {
        guard !finished else { return }
        finished = true
        send(FlagQuizEvent.tutorialSkipped, ["step": String(atStep)])
    }
}

/// Tracks one attempt at a stop or the daily set, from `level_started` to exactly one terminal event
/// (`level_completed`, `level_failed` or `level_abandoned`).
public struct RunAnalytics: Sendable {
    private let context: RunContext
    private let analytics: FlagQuizAnalytics
    private var startedAt: Date
    private var questionShownAt: Date
    private var finished = false
    private var offerShown = false
    private var offerResolved = false

    init(context: RunContext, analytics: FlagQuizAnalytics) {
        self.context = context
        self.analytics = analytics
        self.startedAt = analytics.now
        self.questionShownAt = analytics.now
    }

    private var base: [String: String] {
        var p = [
            "mode": context.mode.rawValue,
            "level_id": context.levelID,
            "attempt_id": context.attemptID,
            "questions": String(context.questionCount)
        ]
        if let chapter = context.chapter { p["chapter"] = chapter }
        if let number = context.stopNumber { p["stop_number"] = String(number) }
        return p
    }

    private func send(_ name: String, _ extra: [String: String] = [:]) {
        analytics.send(name, base.merging(extra) { _, new in new })
    }

    private func summary(_ session: QuizSession) -> [String: String] {
        [
            "score": String(session.score),
            "correct": String(session.correctCount),
            "mistakes": String(session.mistakes),
            "best_streak": String(session.bestStreak),
            "refuels": String(session.refuelsUsed),
            "duration_s": seconds(analytics.now.timeIntervalSince(startedAt))
        ]
    }

    public mutating func start() {
        startedAt = analytics.now
        questionShownAt = startedAt
        send(FlagQuizEvent.levelStarted)
    }

    /// Call when a question appears on screen so `time_ms` measures thinking time, not animation delay.
    public mutating func questionShown() {
        questionShownAt = analytics.now
    }

    /// Call right after `QuizSession.answer`, with the session as it is afterwards.
    public func answered(_ result: QuizSession.AnswerResult, session: QuizSession) {
        let answer = result.question.answer
        let difficulty = CountryCatalog.country(iso2: answer).map { String(FlagCatalog.difficulty(of: $0).rawValue) } ?? "0"
        send(FlagQuizEvent.questionAnswered, [
            "index": String(session.currentIndex - 1),
            "answer": answer,
            "selected": result.selected,
            "correct": result.isCorrect ? "true" : "false",
            "difficulty": difficulty,
            "streak": String(result.streak),
            "fuel": String(session.fuel),
            "time_ms": String(Int((analytics.now.timeIntervalSince(questionShownAt) * 1000).rounded()))
        ])
        if result.state == .outOfFuel {
            send(FlagQuizEvent.fuelExhausted, [
                "index": String(session.currentIndex - 1),
                "can_refuel": session.canRefuel ? "true" : "false"
            ])
        }
    }

    /// The run was won. Sends `level_completed` once.
    public mutating func completed(stars: Int, session: QuizSession) {
        guard !finished else { return }
        finished = true
        send(FlagQuizEvent.levelCompleted, summary(session).merging(["stars": String(stars)]) { _, new in new })
    }

    /// The run ended out of fuel for good (no refuel left, or the player moved on). Sends `level_failed` once.
    public mutating func failed(session: QuizSession) {
        guard !finished else { return }
        finished = true
        send(FlagQuizEvent.levelFailed, summary(session).merging(["reason": "out_of_fuel"]) { _, new in new })
    }

    /// The player left mid-run. Sends `level_abandoned` once.
    public mutating func abandoned(session: QuizSession) {
        guard !finished else { return }
        finished = true
        send(FlagQuizEvent.levelAbandoned, summary(session).merging([
            "progress": String(session.currentIndex)
        ]) { _, new in new })
    }

    // MARK: Rewarded refuel

    private func offerProperties(_ session: QuizSession) -> [String: String] {
        ["placement": Refuel.placement.rawValue, "refuel_number": String(session.refuelsUsed + 1)]
    }

    /// The "watch an ad to keep going" offer appeared. Sent once per offer.
    public mutating func refuelOffered(session: QuizSession) {
        guard !offerShown, session.canRefuel else { return }
        offerShown = true
        send(FlagQuizEvent.rewardOfferShown, offerProperties(session))
    }

    public func refuelAccepted(session: QuizSession) {
        send(FlagQuizEvent.rewardOfferAccepted, offerProperties(session))
    }

    /// The ad flow finished; `session` is the state before the refuel is applied.
    public mutating func refuelResolved(_ outcome: RefuelOutcome, session: QuizSession) {
        switch outcome {
        case .refueled:
            send(FlagQuizEvent.rewardCompleted, offerProperties(session))
            // A later offer (if any) is a new one.
            offerShown = false
            offerResolved = false
        case .cancelled:
            send(FlagQuizEvent.rewardFailed, offerProperties(session).merging(["reason": "cancelled"]) { _, new in new })
        case .unavailable:
            send(FlagQuizEvent.rewardFailed, offerProperties(session).merging(["reason": "unavailable"]) { _, new in new })
        case .ineligible(let reason):
            send(FlagQuizEvent.rewardFailed, offerProperties(session).merging(["reason": "ineligible_\(reason.rawValue)"]) { _, new in new })
        }
    }

    /// The player left the out-of-fuel screen without taking an offer that was shown.
    public mutating func refuelDeclined(session: QuizSession) {
        guard offerShown, !offerResolved else { return }
        offerResolved = true
        send(FlagQuizEvent.rewardOfferDeclined, offerProperties(session))
    }

    /// A counting daily attempt was recorded.
    public func dailyCompleted(score: Int, streak: Int) {
        send(FlagQuizEvent.dailyCompleted, ["score": String(score), "streak": String(streak)])
    }
}

private func seconds(_ interval: TimeInterval) -> String {
    String(max(0, Int(interval.rounded())))
}
