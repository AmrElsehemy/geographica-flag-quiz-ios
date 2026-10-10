import GameTimeServices
import os

/// Writes each event to the unified log (visible in Console.app and Xcode). It keeps events on the
/// device; a real analytics backend can replace it by passing another `AnalyticsClient` to `AppModel`.
struct LoggingAnalyticsClient: AnalyticsClient {
    private static let logger = Logger(subsystem: "ai.knowlly.flagquiz", category: "analytics")

    func track(_ event: AnalyticsEvent) {
        let properties = event.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        Self.logger.info("\(event.name, privacy: .public) \(properties, privacy: .public)")
    }
}
