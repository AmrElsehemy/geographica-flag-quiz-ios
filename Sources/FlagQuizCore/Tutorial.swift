/// The first-run practice round: three iconic flags, hand-picked so nothing is ambiguous, with
/// distractors that look nothing like the answer. The player learns by doing; wrong answers are free.
public enum Tutorial {
    public static let id = "tutorial"

    public struct Step: Equatable, Sendable {
        public let question: Question
        /// Short coaching line shown above the flag for this step.
        public let coach: String
    }

    public static let steps: [Step] = [
        Step(question: Question(answer: "JP", choices: ["BR", "JP", "ES", "EG"]),
             coach: "Tap the country that matches the flag."),
        Step(question: Question(answer: "BR", choices: ["FR", "CA", "BR", "KR"]),
             coach: "Answer in a row to build a streak and earn bonus points."),
        Step(question: Question(answer: "US", choices: ["US", "CN", "DE", "ES"]),
             coach: "Last one! In real stops a wrong answer costs fuel. Here it's free.")
    ]

    /// Fuel is effectively unlimited so the practice round can never end in failure.
    public static func session() -> QuizSession {
        QuizSession(id: id, questions: steps.map(\.question), fuel: 99)
    }

    public static func coach(forQuestionIndex index: Int) -> String? {
        steps.indices.contains(index) ? steps[index].coach : nil
    }
}
