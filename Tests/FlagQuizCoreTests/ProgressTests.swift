import Foundation
import GeographicaCore
import Testing
@testable import FlagQuizCore

@Suite struct ProgressTests {
    private let europe = Adventure.chapters[0]
    private let northAmerica = Adventure.chapters[1]

    @Test func startsWithOnlyTheFirstStopOpen() {
        let p = AdventureProgress()
        #expect(p.isStopUnlocked(europe.stops[0]))
        #expect(!p.isStopUnlocked(europe.stops[1]))
        #expect(!p.isChapterUnlocked(northAmerica))
    }

    @Test func oneStarOpensTheNextStop() {
        var p = AdventureProgress()
        p.record(stars: 1, for: europe.stops[0])
        #expect(p.isStopUnlocked(europe.stops[1]))
        #expect(!p.isStopUnlocked(europe.stops[2]))
    }

    @Test func keepsTheBestResultAndClamps() {
        var p = AdventureProgress()
        p.record(stars: 3, for: europe.stops[0])
        p.record(stars: 1, for: europe.stops[0])
        #expect(p.stars(for: europe.stops[0]) == 3)
        p.record(stars: 9, for: europe.stops[1])
        #expect(p.stars(for: europe.stops[1]) == 3)
    }

    @Test func enoughStarsOpenTheNextChapter() {
        var p = AdventureProgress()
        let needed = Adventure.starsToUnlockNext(after: europe)
        var earned = 0
        for stop in europe.stops where earned < needed {
            p.record(stars: 3, for: stop)
            earned += 3
        }
        #expect(p.isChapterUnlocked(northAmerica))
        #expect(p.isStopUnlocked(northAmerica.stops[0]))
    }

    @Test func dailyStreakCountsConsecutiveDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let day4 = day1.addingTimeInterval(3 * 86_400)

        var p = AdventureProgress()
        p.recordDaily(score: 500, on: day1, calendar: calendar)
        p.recordDaily(score: 900, on: day1, calendar: calendar)   // same day: ignored
        #expect(p.dailyStreak == 1 && p.bestDailyScore == 500)
        p.recordDaily(score: 700, on: day2, calendar: calendar)
        #expect(p.dailyStreak == 2 && p.bestDailyScore == 700)
        p.recordDaily(score: 100, on: day4, calendar: calendar)   // gap resets
        #expect(p.dailyStreak == 1)
    }

    @Test func dailySessionIsSharedPerDayAndDiffersAcrossDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let a = DailyChallenge.session(for: day, calendar: calendar)
        let b = DailyChallenge.session(for: day, calendar: calendar)
        let next = DailyChallenge.session(for: day.addingTimeInterval(86_400), calendar: calendar)
        #expect(a.questions == b.questions)
        #expect(a.questions != next.questions)
        #expect(a.questions.count == DailyChallenge.questionCount)
        #expect(Set(a.questions.map(\.answer)).count == DailyChallenge.questionCount)
    }

    @Test func progressRoundTripsThroughJSON() throws {
        var p = AdventureProgress()
        p.record(stars: 2, for: europe.stops[0])
        let decoded = try JSONDecoder().decode(AdventureProgress.self, from: JSONEncoder().encode(p))
        #expect(decoded == p)
        let store = InMemoryProgressStore()
        store.save(p)
        #expect(store.load() == p)
    }
}
