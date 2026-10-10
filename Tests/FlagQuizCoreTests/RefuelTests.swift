import Foundation
import GameTimeCommerce
import Testing
@testable import FlagQuizCore

private struct FakeAdProvider: AdProviding {
    let available: Bool
    let result: AdPresentationResult
    func isAvailable(for placement: MonetizationPlacement) async -> Bool { available }
    func present(_ placement: MonetizationPlacement) async throws -> AdPresentationResult { result }
}

private func context(canRequestAds: Bool = true) -> MonetizationContext {
    MonetizationContext(canRequestAds: canRequestAds, isOnboarding: false, sessionAge: 600, completedLevels: 0)
}

private func refueler(
    available: Bool = true,
    result: AdPresentationResult = .completed,
    cooldown: TimeInterval = 30
) -> Refueler {
    Refueler(coordinator: MonetizationCoordinator(
        provider: FakeAdProvider(available: available, result: result),
        receipts: InMemoryRewardReceiptStore(),
        policy: MonetizationPolicy(configuration: .init(rewardedCooldown: cooldown))
    ))
}

@Suite struct RefuelTests {
    @Test func watchingTheAdRefuels() async {
        let outcome = await refueler().requestRefuel(attemptID: "a", refuelNumber: 1, context: context())
        #expect(outcome == .refueled)
    }

    @Test func closingTheAdEarlyDoesNotRefuel() async {
        let outcome = await refueler(result: .cancelled).requestRefuel(attemptID: "a", refuelNumber: 1, context: context())
        #expect(outcome == .cancelled)
    }

    @Test func noAdReadyIsReportedHonestly() async {
        let outcome = await refueler(available: false).requestRefuel(attemptID: "a", refuelNumber: 1, context: context())
        #expect(outcome == .unavailable)
    }

    @Test func noConsentMeansNoAd() async {
        let outcome = await refueler().requestRefuel(attemptID: "a", refuelNumber: 1, context: context(canRequestAds: false))
        #expect(outcome == .ineligible(.consentRequired))
    }

    @Test func requestIdsAreStablePerOpportunityAndDistinctAcrossAttempts() {
        #expect(Refuel.request(attemptID: "a", refuelNumber: 1) == Refuel.request(attemptID: "a", refuelNumber: 1))
        #expect(Refuel.request(attemptID: "a", refuelNumber: 1).id != Refuel.request(attemptID: "b", refuelNumber: 1).id)
        #expect(Refuel.request(attemptID: "a", refuelNumber: 1).id != Refuel.request(attemptID: "a", refuelNumber: 2).id)
    }

    @Test func eachOpportunityGrantsOnceEvenIfRequestedTwice() async {
        let r = refueler(cooldown: 0)
        _ = await r.requestRefuel(attemptID: "a", refuelNumber: 1, context: context())
        // A second ask for the same opportunity is acknowledged without showing another ad.
        let again = await r.requestRefuel(attemptID: "a", refuelNumber: 1, context: context())
        #expect(again == .refueled)
    }

    @Test func rewardedAdsRespectTheSharedCooldown() async {
        let r = refueler()
        #expect(await r.requestRefuel(attemptID: "a", refuelNumber: 1, context: context()) == .refueled)
        let next = await r.requestRefuel(attemptID: "b", refuelNumber: 1, context: context())
        #expect(next == .ineligible(.cooldown))
    }

    @Test func sessionAllowsOnlyOneRefuelPerAttempt() {
        let questions = (0..<5).map { Question(answer: "A\($0)", choices: ["A\($0)", "B", "C", "D"]) }
        var s = QuizSession(id: "t", questions: questions)
        for _ in 0..<3 { s.answer("B") }
        #expect(s.canRefuel)
        s.refuel()
        #expect(s.refuelsUsed == 1 && s.state == .inProgress && !s.canRefuel)
        s.answer("B")
        #expect(s.state == .outOfFuel)
        s.refuel()   // second refuel is refused
        #expect(s.state == .outOfFuel && s.refuelsUsed == 1)
    }
}
