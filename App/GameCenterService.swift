@preconcurrency import GameKit
import FlagQuizCore
import Observation
import UIKit

/// Game Center sign-in and the leaderboard screen. Delivering scores is `GameKitScoreSubmitter`'s job,
/// driven by `LeaderboardSubmitter` in FlagQuizCore (which queues scores and retries).
@MainActor
@Observable
final class GameCenterService {
    private(set) var isAuthenticated = false
    /// Called each time a player signs in, so queued scores can be delivered.
    @ObservationIgnored var onAuthenticated: (() -> Void)?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let dismissDelegate = LeaderboardDismissDelegate()

    /// Starts sign-in. Safe to call more than once. Game Center shows its own sign-in UI if needed.
    func start() {
        guard !started else { return }
        started = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                let signedIn = GKLocalPlayer.local.isAuthenticated
                self.isAuthenticated = signedIn
                if signedIn { self.onAuthenticated?() }
            }
        }
    }

    func showLeaderboard() {
        guard isAuthenticated, let top = Self.topViewController() else { return }
        let controller = GKGameCenterViewController(
            leaderboardID: Leaderboard.dailyID, playerScope: .global, timeScope: .today
        )
        controller.gameCenterDelegate = dismissDelegate
        top.present(controller, animated: true)
    }

    #if DEBUG
    /// Demo mode only: show the signed-in UI without talking to Game Center.
    func markAuthenticatedForDemo() { isAuthenticated = true }
    #endif

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

/// GameKit calls this on the main thread, but its protocol isn't main-actor isolated, so the method is
/// `nonisolated` and hops to the main actor to dismiss the screen.
private final class LeaderboardDismissDelegate: NSObject, GKGameCenterControllerDelegate {
    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in
            gameCenterViewController.dismiss(animated: true)
        }
    }
}

/// Sends a score to the daily leaderboard through GameKit.
struct GameKitScoreSubmitter: ScoreSubmitting {
    func submit(score: Int, leaderboardID: String) async throws {
        let player = GKLocalPlayer.local
        guard player.isAuthenticated else { throw ScoreSubmissionError.notAuthenticated }
        try await GKLeaderboard.submitScore(score, context: 0, player: player, leaderboardIDs: [leaderboardID])
    }
}
