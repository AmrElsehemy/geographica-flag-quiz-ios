import Foundation
import GameTimeCore
import GameTimeServices
import GameTimeTesting
import GeographicaCore
import GeographicaFlags
import Testing
@testable import FlagQuizCore

@Suite struct TutorialContentTests {
    @Test func questionsAreWellFormedAndUnambiguous() throws {
        var answers: Set<String> = []
        for step in Tutorial.steps {
            let q = step.question
            #expect(q.choices.count == Question.choiceCount)
            #expect(Set(q.choices).count == Question.choiceCount)
            #expect(q.choices.contains(q.answer))
            #expect(!step.coach.isEmpty)
            answers.insert(q.answer)

            let target = try #require(CountryCatalog.country(iso2: q.answer))
            #expect(FlagCatalog.difficulty(of: target) == .easy, "\(q.answer) should be an easy flag")
            let lookalikes = Set(FlagCatalog.lookalikes(of: target).map(\.iso2))
            #expect(lookalikes.isDisjoint(with: q.choices), "\(q.answer) has a look-alike among its choices")
            for code in q.choices { #expect(CountryCatalog.country(iso2: code) != nil) }
        }
        #expect(answers.count == Tutorial.steps.count)
    }

    @Test func answerIsNotAlwaysInTheSameSlot() {
        let slots = Set(Tutorial.steps.compactMap { $0.question.choices.firstIndex(of: $0.question.answer) })
        #expect(slots.count == Tutorial.steps.count)
    }

    @Test func practiceRoundCannotBeFailed() {
        var s = Tutorial.session()
        for _ in Tutorial.steps {
            let wrong = s.currentQuestion!.choices.first { $0 != s.currentQuestion!.answer }!
            s.answer(wrong)
        }
        #expect(s.state != .outOfFuel)
        guard case .completed = s.state else { Issue.record("tutorial should complete even with every answer wrong"); return }
    }

    @Test func coachLinesAreIndexedAndBounded() {
        #expect(Tutorial.coach(forQuestionIndex: 0) == Tutorial.steps[0].coach)
        #expect(Tutorial.coach(forQuestionIndex: -1) == nil)
        #expect(Tutorial.coach(forQuestionIndex: Tutorial.steps.count) == nil)
    }
}

@Suite struct OnboardingProgressTests {
    private func progress(stars: Int) -> AdventureProgress {
        var p = AdventureProgress()
        if stars > 0 { p.record(stars: stars, for: Adventure.chapters[0].stops[0]) }
        return p
    }

    @Test func newPlayersSeeTheTutorialUntilTheyFinishOrSkip() {
        var o = OnboardingProgress()
        #expect(o.shouldShowTutorial)
        o.skipTutorial()
        #expect(!o.shouldShowTutorial)
        var done = OnboardingProgress()
        done.completeTutorial()
        #expect(!done.shouldShowTutorial)
    }

    @Test func noMapHintsDuringTheTutorial() {
        #expect(OnboardingProgress().mapHint(progress: progress(stars: 0)) == nil)
    }

    @Test func hintsAppearOneAtATimeInOrderAndOnlyOnce() {
        var o = OnboardingProgress()
        o.completeTutorial()
        #expect(o.mapHint(progress: progress(stars: 0)) == .mapStart)
        o.markSeen(.mapStart)
        #expect(o.mapHint(progress: progress(stars: 0)) == nil)
        #expect(o.mapHint(progress: progress(stars: 2)) == .daily)
        o.markSeen(.daily)
        #expect(o.mapHint(progress: progress(stars: 2)) == nil)
    }

    @Test func dailyHintIsSkippedOnceTheDailyHasBeenPlayed() {
        var o = OnboardingProgress()
        o.completeTutorial()
        o.markSeen(.mapStart)
        var p = progress(stars: 1)
        p.recordDaily(score: 100, on: Date())
        #expect(o.mapHint(progress: p) == nil)
    }

    @Test func roundTripsThroughJSONAndStores() throws {
        var o = OnboardingProgress()
        o.completeTutorial()
        o.markSeen(.stars)
        let decoded = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(o))
        #expect(decoded == o)
        let store = InMemoryOnboardingStore()
        store.save(o)
        #expect(store.load() == o)
        let defaults = try #require(UserDefaults(suiteName: "onboarding-tests-\(UUID().uuidString)"))
        let persisted = UserDefaultsOnboardingStore(defaults: defaults)
        #expect(persisted.load().shouldShowTutorial)
        persisted.save(o)
        #expect(persisted.load() == o)
    }
}

@Suite struct TutorialAnalyticsTests {
    @Test func funnelIsStartedStepsThenExactlyOneTerminalEvent() {
        let client = RecordingAnalyticsClient()
        let analytics = FlagQuizAnalytics(client: client)
        var t = analytics.makeTutorial(replay: false)
        t.start()
        t.step(index: 0, correct: true)
        t.step(index: 1, correct: false)
        var s = Tutorial.session()
        for step in Tutorial.steps { s.answer(step.question.answer) }
        t.completed(session: s)
        t.completed(session: s)
        t.skipped(atStep: 3)
        #expect(client.events.map(\.name) == ["tutorial_started", "tutorial_step", "tutorial_step", "tutorial_completed"])
        #expect(client.events.last?.properties["replay"] == "false")
        #expect(client.events[2].properties["correct"] == "false" && client.events[2].properties["step"] == "1")
    }

    @Test func skipReportsHowFarThePlayerGot() {
        let client = RecordingAnalyticsClient()
        var t = FlagQuizAnalytics(client: client).makeTutorial(replay: true)
        t.start()
        t.skipped(atStep: 1)
        t.skipped(atStep: 2)
        let skips = client.events.filter { $0.name == "tutorial_skipped" }
        #expect(skips.count == 1 && skips[0].properties["step"] == "1" && skips[0].properties["replay"] == "true")
    }

    @Test func hintSeenIsReported() {
        let client = RecordingAnalyticsClient()
        FlagQuizAnalytics(client: client).hintSeen(.daily)
        #expect(client.events.first?.name == "hint_seen")
        #expect(client.events.first?.properties["hint"] == "daily")
        #expect(client.events.first?.properties["game"] == "flag_quiz")
    }
}
