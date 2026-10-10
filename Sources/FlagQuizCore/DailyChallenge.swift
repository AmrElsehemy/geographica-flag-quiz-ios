import Foundation
import GameTimeCore
import GeographicaCore
import GeographicaFlags

/// One shared, worldwide set of flags per day.
///
/// "Day" is always a UTC day, never the device's local one, so a player in Cairo, New York and
/// Tokyo who play at the same instant get the same challenge and the same streak boundaries.
public enum DailyChallenge {
    public static let questionCount = 10

    /// The single calendar that defines a daily-challenge day: Gregorian, UTC.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    /// `yyyy-MM-dd` of the UTC day containing `date`.
    public static func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func session(for date: Date) -> QuizSession {
        let key = dayKey(for: date)
        var rng = SeededRandomSource(seed: StableHash.fnv1a("daily-\(key)"))
        let targets = QuestionGenerator.shuffled(CountryCatalog.all, using: &rng).prefix(questionCount)
        let questions = targets.map { QuestionGenerator.question(for: $0, pool: CountryCatalog.all, using: &rng) }
        return QuizSession(id: "daily-\(key)", questions: questions)
    }
}
