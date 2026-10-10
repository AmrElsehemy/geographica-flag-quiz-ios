import FlagQuizCore
import Foundation
import GameTimeServices
import GeographicaCore

/// Debug-only: boots the app straight into a fixed, realistic state so the UI test can capture App
/// Store screenshots from the real app. Release builds contain none of this.
///
///     -demo-state quiz-nepal | quiz-lookalike | home | result-daily | result-stars | tutorial
///
/// Demo mode uses in-memory stores, no analytics, no ads and a separate defaults suite, so it never
/// touches real player data.
enum DemoMode {
    @MainActor
    static func makeModel() -> AppModel? {
        #if DEBUG
        return debugModel()
        #else
        return nil
        #endif
    }
}

#if DEBUG
enum DemoScene: String {
    case quizNepal = "quiz-nepal"
    case quizLookalike = "quiz-lookalike"
    case home
    case resultDaily = "result-daily"
    case resultStars = "result-stars"
    case tutorial

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> DemoScene? {
        guard let flag = arguments.firstIndex(of: "-demo-state"), arguments.indices.contains(flag + 1) else { return nil }
        return DemoScene(rawValue: arguments[flag + 1])
    }
}

extension DemoMode {
    @MainActor
    fileprivate static func debugModel() -> AppModel? {
        guard let scene = DemoScene.fromLaunchArguments() else { return nil }

        let progressStore = InMemoryProgressStore()
        progressStore.save(progress(for: scene))

        var onboarding = OnboardingProgress()
        if scene != .tutorial {
            // Everyone but the tutorial shot has "already been taught", so no hint cards clutter the screen.
            onboarding.completeTutorial()
            Hint.allCases.forEach { onboarding.markSeen($0) }
        }
        let onboardingStore = InMemoryOnboardingStore()
        onboardingStore.save(onboarding)

        let model = AppModel(
            store: progressStore,
            onboardingStore: onboardingStore,
            defaults: UserDefaults(suiteName: "ai.knowlly.flagquiz.demo") ?? .standard,
            analyticsClient: NoOpAnalyticsClient(),
            adsEnabled: false
        )
        model.setDemoRun(run(for: scene))
        return model
    }

    // MARK: Progress

    private static func progress(for scene: DemoScene) -> AdventureProgress {
        var progress = AdventureProgress()
        guard scene == .home else { return progress }

        // Europe mostly starred (enough to open North America), one stop into North America.
        let europe = Adventure.chapters[0].stops
        for (stop, stars) in zip(europe, [3, 3, 2, 3, 3, 2]) { progress.record(stars: stars, for: stop) }
        progress.record(stars: 2, for: Adventure.chapters[1].stops[0])

        // A five-day daily streak ending today.
        for daysAgo in stride(from: 4, through: 0, by: -1) {
            progress.recordDaily(score: 700 + daysAgo * 30, on: Date().addingTimeInterval(-86_400 * Double(daysAgo)))
        }
        return progress
    }

    // MARK: Runs

    private static func run(for scene: DemoScene) -> Run? {
        switch scene {
        case .home, .tutorial:
            return nil   // the map (or the first-launch tutorial) shows by itself
        case .quizNepal:
            guard let stop = Adventure.chapter(for: .asia)?.stops[1] else { return nil }
            let session = answered(3, of: [
                question("JP", ["BR", "JP", "ES", "EG"]),
                question("FR", ["FR", "CA", "KR", "ZA"]),
                question("BR", ["IT", "CL", "BR", "DE"]),
                question("NP", ["TH", "IN", "NP", "JP"]),   // Thailand, India, Nepal, Japan
                question("IN", ["PK", "IN", "ID", "BD"])
            ])
            return Run(kind: .stop(stop), preset: session)
        case .quizLookalike:
            guard let stop = Adventure.chapters[0].stops.last else { return nil }
            let session = answered(2, of: [
                question("DE", ["DE", "BE", "AT", "NL"]),
                question("IT", ["IE", "IT", "MX", "HU"]),
                question("RO", ["TD", "RO", "MD", "AD"]),   // Chad, Romania, Moldova, Andorra
                question("PL", ["PL", "ID", "MC", "AT"]),
                question("NO", ["SE", "NO", "DK", "FI"])
            ])
            return Run(kind: .stop(stop), preset: session)
        case .resultStars:
            let stop = Adventure.chapters[0].stops[3]
            var session = Adventure.session(for: stop)
            while let current = session.currentQuestion { session.answer(current.answer) }
            return Run(kind: .stop(stop), preset: session)
        case .resultDaily:
            var session = DailyChallenge.session(for: Date())
            var index = 0
            while let current = session.currentQuestion {
                // One slip on the fifth flag: two stars, a believable score.
                let pick = index == 4 ? current.choices.first { $0 != current.answer } ?? current.answer : current.answer
                session.answer(pick)
                index += 1
            }
            return Run(kind: .daily(counts: true), preset: session)
        }
    }

    private static func question(_ answer: String, _ choices: [String]) -> Question {
        Question(answer: answer, choices: choices)
    }

    /// A session with its first `count` questions already answered correctly (so a streak shows).
    private static func answered(_ count: Int, of questions: [Question]) -> QuizSession {
        var session = QuizSession(id: "demo", questions: questions)
        for _ in 0..<count { session.answer(session.currentQuestion?.answer ?? "") }
        return session
    }
}
#endif
