import GameTimeCore
import GeographicaCore

/// A run through a fixed list of questions with limited "fuel" (lives).
public struct QuizSession: Sendable {
    public enum State: Equatable, Sendable {
        case inProgress
        case completed(stars: Int)
        case outOfFuel
    }

    public struct AnswerResult: Equatable, Sendable {
        public let question: Question
        public let selected: String
        public let isCorrect: Bool
        public let pointsAwarded: Int
        public let streak: Int
        public let state: State
    }

    public static let startingFuel = 3
    public static let pointsPerCorrect = 100
    public static let streakBonus = 10
    public static let maxStreakBonusSteps = 5
    /// A player may continue once per attempt after running dry; beyond that they retry.
    public static let maxRefuels = 1

    public let id: String
    public let questions: [Question]
    public private(set) var currentIndex = 0
    public private(set) var fuel: Int
    public private(set) var streak = 0
    public private(set) var bestStreak = 0
    public private(set) var mistakes = 0
    public private(set) var correctCount = 0
    public private(set) var score = 0
    public private(set) var state: State = .inProgress
    public private(set) var refuelsUsed = 0

    public init(id: String, questions: [Question], fuel: Int = QuizSession.startingFuel) {
        self.id = id
        self.questions = questions
        self.fuel = fuel
        if questions.isEmpty { state = .completed(stars: Self.stars(forMistakes: 0)) }
    }

    public var currentQuestion: Question? {
        state == .inProgress && currentIndex < questions.count ? questions[currentIndex] : nil
    }

    public var progress: Double {
        questions.isEmpty ? 1 : Double(currentIndex) / Double(questions.count)
    }

    /// Records an answer for the current question and moves on. Returns `nil` if the session is over.
    @discardableResult
    public mutating func answer(_ selected: String) -> AnswerResult? {
        guard let question = currentQuestion else { return nil }
        let isCorrect = selected == question.answer
        var points = 0

        if isCorrect {
            streak += 1
            bestStreak = max(bestStreak, streak)
            correctCount += 1
            points = Self.pointsPerCorrect + Self.streakBonus * min(streak - 1, Self.maxStreakBonusSteps)
            score += points
        } else {
            streak = 0
            mistakes += 1
            fuel -= 1
        }

        currentIndex += 1
        if fuel <= 0 {
            state = .outOfFuel
        } else if currentIndex >= questions.count {
            state = .completed(stars: Self.stars(forMistakes: mistakes))
        }

        return AnswerResult(question: question, selected: selected, isCorrect: isCorrect,
                            pointsAwarded: points, streak: streak, state: state)
    }

    public var canRefuel: Bool { state == .outOfFuel && refuelsUsed < Self.maxRefuels }

    /// Continues after running dry (e.g. after a rewarded ad). Grants one fuel, once per attempt.
    public mutating func refuel() {
        guard canRefuel else { return }
        refuelsUsed += 1
        fuel = 1
        state = currentIndex >= questions.count
            ? .completed(stars: Self.stars(forMistakes: mistakes))
            : .inProgress
    }

    public static func stars(forMistakes mistakes: Int) -> Int {
        switch mistakes {
        case ...0: 3
        case 1: 2
        default: 1
        }
    }
}

extension Adventure {
    /// A reproducible session for `stop`: the same stop always asks the same questions in the same order.
    public static func session(for stop: Stop) -> QuizSession {
        var rng = SeededRandomSource(seed: StableHash.fnv1a(stop.id))
        let pool = CountryCatalog.countries(in: stop.continent)
        let targets = stop.countryCodes.compactMap(CountryCatalog.country(iso2:))
        let questions = targets.map { QuestionGenerator.question(for: $0, pool: pool, using: &rng) }
        return QuizSession(id: stop.id, questions: questions)
    }
}

enum StableHash {
    /// 64-bit FNV-1a. `Hashable.hashValue` is randomised per launch, so it can't seed anything reproducible.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
