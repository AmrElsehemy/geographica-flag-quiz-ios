import GameTimeCore
import GeographicaCore
import Testing
@testable import FlagQuizCore

@Suite struct QuestionTests {
    @Test func everyCountryGetsAValidQuestion() {
        var rng = SeededRandomSource(seed: 7)
        for country in CountryCatalog.all {
            let pool = CountryCatalog.countries(in: country.continent)
            let q = QuestionGenerator.question(for: country, pool: pool, using: &rng)
            #expect(q.answer == country.iso2)
            #expect(q.choices.count == Question.choiceCount)
            #expect(Set(q.choices).count == Question.choiceCount, "duplicate choice for \(country.iso2)")
            #expect(q.choices.contains(country.iso2))
        }
    }

    @Test func hardFlagsGetLookalikeDistractors() throws {
        let romania = try #require(CountryCatalog.country(iso2: "RO"))
        var rng = SeededRandomSource(seed: 1)
        let q = QuestionGenerator.question(for: romania, pool: CountryCatalog.all, using: &rng)
        let lookalikes: Set<String> = ["TD", "AD", "MD"]
        #expect(q.choices.filter { lookalikes.contains($0) }.count >= 2)
    }

    @Test func sameSeedGivesSameQuestions() {
        let stop = Adventure.chapters[0].stops[0]
        #expect(Adventure.session(for: stop).questions == Adventure.session(for: stop).questions)
    }

    @Test func answerPositionIsNotAlwaysFirst() {
        let positions = Adventure.chapters.flatMap(\.stops).flatMap { Adventure.session(for: $0).questions }
            .compactMap { $0.choices.firstIndex(of: $0.answer) }
        #expect(Set(positions).count == Question.choiceCount)
    }
}
