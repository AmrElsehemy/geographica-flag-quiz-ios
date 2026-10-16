import FlagQuizCore
import Foundation
import GameTimeCommerce

/// The app's ad stack. Version 1.0 ships without ads (no ad network has approved the account yet), so
/// this wires the shared monetisation coordinator to a no-op provider and reports `isEnabled == false`;
/// the UI uses that to hide the "watch an ad" offer. To turn ads on later, add an ad provider package
/// (the kit has `GameTimeAdMob` and `GameTimeAppLovin`), give this a real provider and consent step,
/// and return true from `isEnabled`. All policy (cooldown, exactly-once rewards) lives in GameTimeKit.
@MainActor
final class AdService {
    let isEnabled = false
    private let refueler = Refueler(coordinator: MonetizationCoordinator(
        provider: NoOpAdProvider(),
        receipts: InMemoryRewardReceiptStore()
    ))
    private let launchedAt = Date()

    func prepare() async {}

    var privacyOptionsRequired: Bool { false }

    func presentPrivacyOptions() async {}

    func requestRefuel(attemptID: String, refuelNumber: Int, completedStops: Int) async -> RefuelOutcome {
        let context = MonetizationContext(
            canRequestAds: false,
            isOnboarding: false,
            sessionAge: Date().timeIntervalSince(launchedAt),
            completedLevels: completedStops
        )
        return await refueler.requestRefuel(attemptID: attemptID, refuelNumber: refuelNumber, context: context)
    }
}
