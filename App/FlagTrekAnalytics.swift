import FlagQuizCore
import Foundation
import GameTimeAnalytics
import GameTimeServices
import UIKit

/// Builds the app's analytics pipeline (GameTimeKit's `AnalyticsPipeline`): events are kept in
/// `Application Support/FlagTrek/events.jsonl` and, while the player leaves sharing on (the default;
/// Settings has the switch), sent anonymously to the studio's PostHog project. A build without
/// `PostHogAPIKey` in its Info.plist sends nothing.
enum FlagTrekAnalytics {
    @MainActor
    static func makePipeline(bundle: Bundle = .main) -> AnalyticsPipeline {
        let info = bundle.infoDictionary ?? [:]
        let context = AnalyticsPipeline.Context(
            game: FlagQuizEvent.gameID,
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            idiom: UIDevice.current.userInterfaceIdiom == .pad ? "pad" : "phone",
            osMajor: UIDevice.current.systemVersion.split(separator: ".").first.map(String.init) ?? "?",
            language: Locale.current.language.languageCode?.identifier ?? "?",
            schemaVersion: Int(FlagQuizEvent.schemaVersion) ?? 1
        )
        var clients: [any AnalyticsClient] = []
        if let configuration = PostHogConfiguration(infoDictionary: info) {
            clients.append(PostHogAnalyticsClient(
                configuration: configuration,
                queueFileURL: PostHogAnalyticsClient.standardQueueURL(directory: "FlagTrek")
            ))
        }
        #if DEBUG
        clients.append(LoggingAnalyticsClient())
        #endif
        return AnalyticsPipeline(
            store: FileEventStore(fileURL: FileEventStore.standardURL(directory: "FlagTrek")),
            clients: clients,
            context: context,
            keyPrefix: "flagquiz.analytics",
            sharingByDefault: true
        )
    }
}
