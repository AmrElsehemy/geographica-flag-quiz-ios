import GameTimeCore
import GeographicaCore
import GeographicaFlags

/// "Which country does this flag belong to?" with four ISO-coded choices.
public struct Question: Hashable, Identifiable, Sendable {
    public var id: String { answer }
    /// ISO code of the country whose flag is shown.
    public let answer: String
    public let choices: [String]

    public static let choiceCount = 4

    public init(answer: String, choices: [String]) {
        self.answer = answer
        self.choices = choices
    }
}

public enum QuestionGenerator {
    /// Builds a question for `target`. Harder flags get more look-alike distractors; the rest are
    /// drawn from the same continent (then the world) so wrong answers stay plausible.
    public static func question<R: GameTimeRandomSource>(
        for target: Country,
        pool: [Country],
        using rng: inout R
    ) -> Question {
        let needed = Question.choiceCount - 1
        let lookalikeBudget: Int
        switch FlagCatalog.difficulty(of: target) {
        case .easy: lookalikeBudget = 0
        case .medium: lookalikeBudget = 1
        case .hard: lookalikeBudget = 2
        }

        var chosen: [String] = []
        func add(_ countries: [Country], limit: Int) {
            for country in countries where chosen.count < limit && country.iso2 != target.iso2 && !chosen.contains(country.iso2) {
                chosen.append(country.iso2)
            }
        }

        add(shuffled(FlagCatalog.lookalikes(of: target), using: &rng), limit: lookalikeBudget)
        add(shuffled(pool.filter { $0.continent == target.continent }, using: &rng), limit: needed)
        add(shuffled(pool, using: &rng), limit: needed)
        add(shuffled(CountryCatalog.all, using: &rng), limit: needed)

        let choices = shuffled(chosen + [target.iso2], using: &rng)
        return Question(answer: target.iso2, choices: choices)
    }

    /// Fisher–Yates shuffle driven by the injected random source, so questions are reproducible.
    static func shuffled<T, R: GameTimeRandomSource>(_ items: [T], using rng: inout R) -> [T] {
        var items = items
        guard items.count > 1 else { return items }
        for index in stride(from: items.count - 1, to: 0, by: -1) {
            let other = Int(rng.nextUInt64() % UInt64(index + 1))
            items.swapAt(index, other)
        }
        return items
    }
}
