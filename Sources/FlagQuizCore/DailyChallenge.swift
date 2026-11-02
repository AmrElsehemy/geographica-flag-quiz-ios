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

    /// What defines a daily-challenge day (GameTimeKit's shared daily calendar): UTC, never the device's day.
    public static let dailyCalendar = DailyCalendar.utc

    /// A Gregorian calendar in the same UTC zone, for building dates in tests and tools.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dailyCalendar.timeZone
        return calendar
    }()

    /// The UTC day containing `date`.
    public static func day(for date: Date) -> DailyDay { dailyCalendar.day(for: date) }

    /// `yyyy-MM-dd` of the UTC day containing `date`.
    public static func dayKey(for date: Date) -> String { day(for: date).key }

    public static func session(for date: Date) -> QuizSession {
        let key = dayKey(for: date)
        var rng = SeededRandomSource(seed: StableHash.fnv1a("daily-\(key)"))
        let targets = QuestionGenerator.shuffled(CountryCatalog.all, using: &rng).prefix(questionCount)
        let questions = targets.map { QuestionGenerator.question(for: $0, pool: CountryCatalog.all, using: &rng) }
        return QuizSession(id: "daily-\(key)", questions: questions)
    }
}
