import GameTimeCommerce

/// The rewarded "refuel" offer: watch an ad, get one more fuel to keep going after running dry.
public enum Refuel {
    public static let offer = RewardOffer(id: "flagquiz.refuel", kind: "fuel", amount: 1)
    public static let placement = MonetizationPlacement.rewardedContinue

    /// The exactly-once key identifies the *opportunity* (this attempt, this refuel), not the tap, so
    /// retrying a failed ad can't double-grant but a brand-new attempt can earn again.
    public static func request(attemptID: String, refuelNumber: Int) -> RewardRequest {
        RewardRequest(offer: offer, opportunity: "attempt:\(attemptID):refuel:\(refuelNumber)")
    }
}

public enum RefuelOutcome: Equatable, Sendable {
    /// The player earned the reward; grant the fuel.
    case refueled
    /// No ad ready (offline, no fill, still loading) or presentation failed.
    case unavailable
    /// The player closed the ad before earning the reward.
    case cancelled
    /// Policy or consent forbids showing an ad right now.
    case ineligible(MonetizationIneligibilityReason)
}

/// Turns the shared monetisation coordinator's result into what this game cares about.
public struct Refueler: Sendable {
    private let coordinator: MonetizationCoordinator

    public init(coordinator: MonetizationCoordinator) {
        self.coordinator = coordinator
    }

    public func requestRefuel(attemptID: String, refuelNumber: Int, context: MonetizationContext) async -> RefuelOutcome {
        let outcome = await coordinator.attempt(
            Refuel.request(attemptID: attemptID, refuelNumber: refuelNumber),
            placement: Refuel.placement,
            context: context
        )
        return Self.map(outcome)
    }

    static func map(_ outcome: MonetizationOutcome) -> RefuelOutcome {
        switch outcome {
        case .granted, .alreadyGranted: .refueled
        case .cancelled: .cancelled
        case .ineligible(let reason): .ineligible(reason)
        case .unavailable, .failed, .busy: .unavailable
        }
    }
}
