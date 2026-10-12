import FlagQuizCore
import Foundation
import GameTimeAdMob
import GameTimeCommerce

/// Owns the app's ad stack: consent, the AdMob provider and the shared monetisation coordinator.
/// All policy (consent, cooldown, exactly-once rewards) lives in GameTimeKit; this only wires it up.
@MainActor
final class AdService {
    private let consent = AdConsent()
    private let provider: AdMobRewardedProvider
    private let refueler: Refueler
    private let launchedAt = Date()
    private var prepared = false

    init() {
        let provider = AdMobRewardedProvider(configuration: Self.configuration())
        self.provider = provider
        self.refueler = Refueler(coordinator: MonetizationCoordinator(
            provider: provider,
            receipts: InMemoryRewardReceiptStore()
        ))
    }

    /// Launch order required by the kit: consent first, then start the SDK (which begins preloading).
    func prepare() async {
        guard !prepared else { return }
        prepared = true
        if await consent.gatherConsent() { provider.start() }
    }

    var privacyOptionsRequired: Bool { consent.privacyOptionsRequired }

    func presentPrivacyOptions() async { await consent.presentPrivacyOptions() }

    func requestRefuel(attemptID: String, refuelNumber: Int, completedStops: Int) async -> RefuelOutcome {
        let context = MonetizationContext(
            canRequestAds: consent.canRequestAds,
            isOnboarding: false,
            sessionAge: Date().timeIntervalSince(launchedAt),
            completedLevels: completedStops
        )
        return await refueler.requestRefuel(attemptID: attemptID, refuelNumber: refuelNumber, context: context)
    }

    /// Debug builds use Google's sample units. Release builds use sample units only when built in
    /// `test` mode (TestFlight builds, so testers can try the rewarded ad). Otherwise they use the unit
    /// id from Info.plist (`FlagQuizRewardedUnitID`) and show no ads at all if it is missing, so a
    /// sample unit can never reach the App Store by accident (the release preflight enforces this too).
    private static func configuration() -> AdMobConfiguration {
        #if DEBUG
        return .testing
        #else
        if Bundle.main.object(forInfoDictionaryKey: "FlagQuizAdsMode") as? String == "test" {
            return .testing
        }
        let id = Bundle.main.object(forInfoDictionaryKey: "FlagQuizRewardedUnitID") as? String
        guard let id, !id.isEmpty else { return AdMobConfiguration(rewardedUnitIDs: [:]) }
        return AdMobConfiguration(rewardedUnitIDs: [Refuel.placement: id])
        #endif
    }
}
