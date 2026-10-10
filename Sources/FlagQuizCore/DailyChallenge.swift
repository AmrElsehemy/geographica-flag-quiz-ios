import Foundation
import GameTimeCore
import GeographicaCore
import GeographicaFlags

/// One shared, worldwide set of flags per calendar day.
public enum DailyChallenge {
    public static let questionCount = 10

    /// `yyyy-MM-dd` in the supplied calendar's time zone.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func session(for date: Date, calendar: Calendar = .current) -> QuizSession {
        let key = dayKey(for: date, calendar: calendar)
        var rng = SeededRandomSource(seed: StableHash.fnv1a("daily-\(key)"))
        let targets = QuestionGenerator.shuffled(CountryCatalog.all, using: &rng).prefix(questionCount)
        let questions = targets.map { QuestionGenerator.question(for: $0, pool: CountryCatalog.all, using: &rng) }
        return QuizSession(id: "daily-\(key)", questions: questions)
    }
}
