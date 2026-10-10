import Testing
@testable import FlagQuizCore

@Suite struct QuizSessionTests {
    private func session(count: Int = 5) -> QuizSession {
        let questions = (0..<count).map { Question(answer: "A\($0)", choices: ["A\($0)", "B", "C", "D"]) }
        return QuizSession(id: "t", questions: questions)
    }

    private func wrong(_ s: QuizSession) -> String { s.currentQuestion!.choices.first { $0 != s.currentQuestion!.answer }! }

    @Test func perfectRunIsThreeStarsWithStreakBonus() {
        var s = session()
        for _ in 0..<5 { s.answer(s.currentQuestion!.answer) }
        #expect(s.state == .completed(stars: 3))
        #expect(s.bestStreak == 5)
        #expect(s.score == 100 + 110 + 120 + 130 + 140)
        #expect(s.currentQuestion == nil)
    }

    @Test func mistakesReduceStars() {
        var one = session()
        one.answer(wrong(one))
        for _ in 0..<4 { one.answer(one.currentQuestion!.answer) }
        #expect(one.state == .completed(stars: 2))

        var two = session()
        two.answer(wrong(two)); two.answer(wrong(two))
        for _ in 0..<3 { two.answer(two.currentQuestion!.answer) }
        #expect(two.state == .completed(stars: 1))
    }

    @Test func wrongAnswerResetsStreakAndCostsFuel() {
        var s = session()
        s.answer(s.currentQuestion!.answer)
        let result = s.answer(wrong(s))
        #expect(result?.isCorrect == false)
        #expect(s.streak == 0)
        #expect(s.fuel == QuizSession.startingFuel - 1)
    }

    @Test func runningOutOfFuelEndsTheSession() {
        var s = session()
        for _ in 0..<3 { s.answer(wrong(s)) }
        #expect(s.state == .outOfFuel)
        #expect(s.answer("A3") == nil)
    }

    @Test func refuelContinuesTheRun() {
        var s = session()
        for _ in 0..<3 { s.answer(wrong(s)) }
        s.refuel()
        #expect(s.state == .inProgress)
        for _ in 0..<2 { s.answer(s.currentQuestion!.answer) }
        #expect(s.state == .completed(stars: 1))
    }

    @Test func refuelAfterFailingOnTheLastQuestionCompletes() {
        var s = session(count: 3)
        for _ in 0..<3 { s.answer(wrong(s)) }
        #expect(s.state == .outOfFuel)
        s.refuel()
        #expect(s.state == .completed(stars: 1))
    }

    @Test func refuelIsIgnoredUnlessOutOfFuel() {
        var s = session()
        s.refuel()
        #expect(s.fuel == QuizSession.startingFuel)
    }
}
