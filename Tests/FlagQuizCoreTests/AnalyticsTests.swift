import Foundation
import GameTimeCommerce
import GameTimeCore
import GameTimeServices
import GameTimeTesting
import Testing
@testable import FlagQuizCore

private final class TestClock: GameTimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

private struct Harness {
    let client = RecordingAnalyticsClient()
    let clock = TestClock()
    var analytics: FlagQuizAnalytics { FlagQuizAnalytics(client: client, clock: clock) }
    var events: [AnalyticsEvent] { client.events }
    var names: [String] { events.map(\.name) }
    func event(_ name: String) -> AnalyticsEvent? { events.first { $0.name == name } }
}

private func session(_ count: Int = 3) -> QuizSession {
    QuizSession(id: "europe-1", questions: (0..<count).map {
        Question(answer: "FR", choices: ["FR", "DE", "IT", "ES"]).with(id: $0)
    })
}

private extension Question {
    /// Distinct questions that all resolve to real countries.
    func with(id index: Int) -> Question {
        let codes = ["FR", "DE", "IT", "ES", "PT"]
        let code = codes[index % codes.count]
        return Question(answer: code, choices: [code] + codes.filter { $0 != code }.prefix(3))
    }
}

private func context(_ session: QuizSession, mode: RunMode = .adventure) -> RunContext {
    RunContext(mode: mode, levelID: session.id, attemptID: "attempt-1", questionCount: session.questions.count,
               chapter: "europe", stopNumber: 1)
}

@Suite struct AnalyticsTests {
    @Test func sessionStartAndEndAreIdempotentAndTimed() {
        let h = Harness()
        var tracker = h.analytics.makeSession()
        tracker.becameActive()
        tracker.becameActive()
        h.clock.advance(95)
        tracker.wentToBackground()
        tracker.wentToBackground()
        #expect(h.names == ["session_start", "session_end"])
        #expect(h.event("session_end")?.properties["duration_s"] == "95")
    }

    @Test func everyEventCarriesGameAndSchema() {
        let h = Harness()
        var tracker = h.analytics.makeSession()
        tracker.becameActive()
        var run = h.analytics.makeRun(context(session()))
        run.start()
        for event in h.events {
            #expect(event.properties["game"] == "flag_quiz")
            #expect(event.properties["schema"] == FlagQuizEvent.schemaVersion)
        }
    }

    @Test func answersReportCorrectnessTimingAndDifficulty() {
        let h = Harness()
        var s = session()
        var run = h.analytics.makeRun(context(s))
        run.start()
        run.questionShown()
        h.clock.advance(2.5)
        let right = s.answer("FR")!
        run.answered(right, session: s)
        run.questionShown()
        h.clock.advance(1)
        let wrong = s.answer("ES")!
        run.answered(wrong, session: s)

        let answers = h.events.filter { $0.name == "question_answered" }
        #expect(answers.count == 2)
        #expect(answers[0].properties["correct"] == "true")
        #expect(answers[0].properties["time_ms"] == "2500")
        #expect(answers[0].properties["index"] == "0")
        #expect(answers[0].properties["difficulty"] == "1")   // France is an easy flag
        #expect(answers[1].properties["correct"] == "false")
        #expect(answers[1].properties["selected"] == "ES" && answers[1].properties["answer"] == "DE")
        #expect(answers[1].properties["fuel"] == "2" && answers[1].properties["streak"] == "0")
    }

    @Test func completedRunSendsExactlyOneTerminalEvent() {
        let h = Harness()
        var s = session(2)
        var run = h.analytics.makeRun(context(s))
        run.start()
        h.clock.advance(30)
        for _ in 0..<2 { if let r = s.answer(s.currentQuestion!.answer) { run.answered(r, session: s) } }
        guard case .completed(let stars) = s.state else { Issue.record("not completed"); return }
        run.completed(stars: stars, session: s)
        run.completed(stars: stars, session: s)
        run.abandoned(session: s)
        #expect(h.names.filter { ["level_completed", "level_failed", "level_abandoned"].contains($0) } == ["level_completed"])
        let done = h.event("level_completed")!.properties
        #expect(done["stars"] == "3" && done["correct"] == "2" && done["mistakes"] == "0")
        #expect(done["duration_s"] == "30" && done["mode"] == "adventure" && done["stop_number"] == "1")
        #expect(done["attempt_id"] == "attempt-1" && done["chapter"] == "europe")
    }

    @Test func runningOutOfFuelSendsFuelExhaustedThenFailed() {
        let h = Harness()
        var s = session(5)
        var run = h.analytics.makeRun(context(s))
        run.start()
        for _ in 0..<3 {
            let wrong = s.currentQuestion!.choices.first { $0 != s.currentQuestion!.answer }!
            if let r = s.answer(wrong) { run.answered(r, session: s) }
        }
        #expect(h.names.filter { $0 == "fuel_exhausted" }.count == 1)
        #expect(h.event("fuel_exhausted")?.properties["can_refuel"] == "true")
        run.failed(session: s)
        run.failed(session: s)
        #expect(h.names.filter { $0 == "level_failed" }.count == 1)
        #expect(h.event("level_failed")?.properties["reason"] == "out_of_fuel")
    }

    @Test func abandoningMidRunReportsProgress() {
        let h = Harness()
        var s = session(5)
        var run = h.analytics.makeRun(context(s))
        run.start()
        if let r = s.answer("FR") { run.answered(r, session: s) }
        run.abandoned(session: s)
        #expect(h.event("level_abandoned")?.properties["progress"] == "1")
        #expect(h.names.contains("level_completed") == false)
    }

    @Test func rewardedRefuelFunnelIsShownAcceptedCompleted() {
        let h = Harness()
        var s = session(5)
        var run = h.analytics.makeRun(context(s))
        run.start()
        for _ in 0..<3 { if let r = s.answer("ZZ") { run.answered(r, session: s) } }
        run.refuelOffered(session: s)
        run.refuelOffered(session: s)   // re-render: still one offer
        run.refuelAccepted(session: s)
        run.refuelResolved(.cancelled, session: s)
        run.refuelAccepted(session: s)
        run.refuelResolved(.refueled, session: s)
        #expect(h.names.filter { $0.hasPrefix("reward_") } == [
            "reward_offer_shown", "reward_offer_accepted", "reward_failed",
            "reward_offer_accepted", "reward_completed"
        ])
        #expect(h.events.first { $0.name == "reward_failed" }?.properties["reason"] == "cancelled")
        #expect(h.event("reward_offer_shown")?.properties["placement"] == "rewardedContinue")
    }

    @Test func declinedOfferIsReportedOnlyIfOneWasShownAndNotTaken() {
        let h = Harness()
        var s = session(5)
        var run = h.analytics.makeRun(context(s))
        run.start()
        run.refuelDeclined(session: s)   // never shown
        for _ in 0..<3 { if let r = s.answer("ZZ") { run.answered(r, session: s) } }
        run.refuelOffered(session: s)
        run.refuelDeclined(session: s)
        run.refuelDeclined(session: s)
        #expect(h.names.filter { $0 == "reward_offer_declined" }.count == 1)
    }

    @Test func ineligibleReasonsAreReportedAsTheyAre() {
        let h = Harness()
        var s = session(5)
        var run = h.analytics.makeRun(context(s))
        run.start()
        for _ in 0..<3 { if let r = s.answer("ZZ") { run.answered(r, session: s) } }
        run.refuelResolved(.ineligible(.consentRequired), session: s)
        #expect(h.event("reward_failed")?.properties["reason"] == "ineligible_consentRequired")
    }

    @Test func dailyAndPracticeAreDistinguishedByMode() {
        let h = Harness()
        let s = session()
        var counting = h.analytics.makeRun(RunContext.daily(counts: true, session: s, attemptID: "a"))
        var practice = h.analytics.makeRun(RunContext.daily(counts: false, session: s, attemptID: "b"))
        counting.start(); practice.start()
        counting.dailyCompleted(score: 640, streak: 3)
        let modes = h.events.filter { $0.name == "level_started" }.compactMap { $0.properties["mode"] }
        #expect(modes == ["daily", "daily_practice"])
        #expect(h.event("daily_completed")?.properties["score"] == "640")
        #expect(h.event("daily_completed")?.properties["streak"] == "3")
    }

    @Test func eventsContainNoPersonalData() {
        let h = Harness()
        var s = session()
        var run = h.analytics.makeRun(context(s))
        run.start()
        if let r = s.answer("FR") { run.answered(r, session: s) }
        let allowed: Set<String> = [
            "game", "schema", "mode", "level_id", "attempt_id", "questions", "chapter", "stop_number", "index",
            "answer", "selected", "correct", "difficulty", "streak", "fuel", "time_ms"
        ]
        for event in h.events { #expect(Set(event.properties.keys).isSubset(of: allowed), "\(event.name)") }
    }
}
