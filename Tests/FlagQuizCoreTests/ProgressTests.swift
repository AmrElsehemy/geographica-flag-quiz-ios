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

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        DailyChallenge.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// `#expect` can't contain a mutating call, so record first and return whether it counted.
    private func record(_ p: inout AdventureProgress, _ score: Int, _ date: Date) -> Bool {
        p.recordDaily(score: score, on: date)
    }

    @Test func dailyStreakCountsConsecutiveDays() {
        var p = AdventureProgress()
        let first = record(&p, 500, utc(2026, 10, 10))
        #expect(first)
        #expect(p.dailyStreak == 1 && p.bestDailyScore == 500)
        let second = record(&p, 700, utc(2026, 10, 11))
        #expect(second)
        #expect(p.dailyStreak == 2 && p.bestDailyScore == 700)
        let afterGap = record(&p, 100, utc(2026, 10, 14))
        #expect(afterGap)
        #expect(p.dailyStreak == 1 && p.bestDailyScore == 700)
    }

    @Test func onlyTheFirstAttemptOfADayCounts() {
        var p = AdventureProgress()
        let first = record(&p, 400, utc(2026, 10, 10, 9))
        let practice = record(&p, 900, utc(2026, 10, 10, 20))
        #expect(first)
        #expect(!practice)
        #expect(p.dailyScore(on: utc(2026, 10, 10)) == 400)
        #expect(p.bestDailyScore == 400 && p.dailyStreak == 1)
        #expect(p.dailyScore(on: utc(2026, 10, 11)) == nil)
    }

    @Test func displayedStreakDropsToZeroOnceADayIsMissed() {
        var p = AdventureProgress()
        _ = record(&p, 500, utc(2026, 10, 10))
        _ = record(&p, 600, utc(2026, 10, 11))
        #expect(p.displayedDailyStreak(on: utc(2026, 10, 11, 23)) == 2, "Played today")
        #expect(p.displayedDailyStreak(on: utc(2026, 10, 12, 8)) == 2, "Today's daily is still open")
        #expect(p.displayedDailyStreak(on: utc(2026, 10, 13)) == 0, "Yesterday was missed")
        #expect(p.dailyStreak == 2, "The saved count is untouched until the next daily")
        #expect(AdventureProgress().displayedDailyStreak(on: utc(2026, 10, 13)) == 0)
    }

    @Test func aDailyOnAnEarlierDayThanTheLastOneDoesNotCount() {
        var p = AdventureProgress()
        _ = record(&p, 500, utc(2026, 10, 10))
        let clockSetBack = record(&p, 900, utc(2026, 10, 8))
        #expect(!clockSetBack)
        #expect(p.lastDailyKey == "2026-10-10" && p.bestDailyScore == 500 && p.dailyStreak == 1)
    }

    @Test func savedProgressFromBeforeTheSharedStreakStillLoads() throws {
        // A save written by the previous build: the format is unchanged.
        let saved = Data(#"{"starsByStop":{},"lastDailyKey":"2026-10-11","dailyStreak":4,"bestDailyScore":820,"lastDailyScore":610}"#.utf8)
        var p = try JSONDecoder().decode(AdventureProgress.self, from: saved)
        #expect(p.dailyStreak == 4 && p.displayedDailyStreak(on: utc(2026, 10, 12)) == 4)
        _ = record(&p, 700, utc(2026, 10, 12))
        #expect(p.dailyStreak == 5, "The streak carries on from the old save")
        let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any]
        #expect(reencoded?["lastDailyKey"] as? String == "2026-10-12")
        #expect(reencoded?["dailyStreak"] as? Int == 5)
    }

    /// Recorded from the build before the daily code moved to GameTimeKit: the same day must still
    /// give every player the same flags.
    @Test func dailyFlagsAreUnchangedByTheSharedDailyCode() {
        let expected = [
            "2026-10-10": "NE,LU,UY,TH,EG,ID,PG,ML,BJ,BY",
            "2026-12-31": "SL,LV,PH,TT,CY,AL,AU,SE,CN,SD",
            "2027-03-01": "LV,UG,GY,MU,CU,NZ,HU,MG,TG,BB",
        ]
        for (key, answers) in expected {
            let parts = key.split(separator: "-").compactMap { Int($0) }
            let flags = DailyChallenge.session(for: utc(parts[0], parts[1], parts[2])).questions.map(\.answer)
            #expect(flags.joined(separator: ",") == answers, "\(key)")
        }
    }

    @Test func dailyDayIsTheUTCDayNotTheDevicesLocalDay() {
        // 23:30 UTC on the 10th is already the 11th in Tokyo and still the 10th in New York.
        let instant = utc(2026, 10, 10, 23, 30)
        #expect(DailyChallenge.dayKey(for: instant) == "2026-10-10")
        #expect(DailyChallenge.dayKey(for: utc(2026, 10, 11, 0, 5)) == "2026-10-11")

        var tokyo = Calendar(identifier: .gregorian); tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(tokyo.component(.day, from: instant) == 11)      // proves local days really differ
        #expect(newYork.component(.day, from: instant) == 10)
        // ...yet everyone gets the same challenge for that instant.
        #expect(DailyChallenge.session(for: instant).questions == DailyChallenge.session(for: utc(2026, 10, 10, 1)).questions)
    }

    @Test func dailySessionIsSharedPerDayAndDiffersAcrossDays() {
        let a = DailyChallenge.session(for: utc(2026, 10, 10))
        let b = DailyChallenge.session(for: utc(2026, 10, 10, 3))
        let next = DailyChallenge.session(for: utc(2026, 10, 11))
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
