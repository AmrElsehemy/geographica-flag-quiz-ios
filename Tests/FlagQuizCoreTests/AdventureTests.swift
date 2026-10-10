import GeographicaCore
import Testing
@testable import FlagQuizCore

@Suite struct AdventureTests {
    @Test func everyCountryAppearsInExactlyOneStop() {
        let codes = Adventure.chapters.flatMap(\.stops).flatMap(\.countryCodes)
        #expect(codes.count == CountryCatalog.all.count)
        #expect(Set(codes).count == codes.count)
    }

    @Test func stopsHaveBetweenThreeAndSevenFlagsAndStayInTheirContinent() {
        for chapter in Adventure.chapters {
            for stop in chapter.stops {
                #expect((3...7).contains(stop.countryCodes.count), "\(stop.id)")
                for code in stop.countryCodes {
                    #expect(CountryCatalog.country(iso2: code)?.continent == chapter.continent)
                }
            }
        }
    }

    @Test func stopIDsAreStableAndLookUpable() {
        #expect(Adventure.stop(id: "europe-1")?.number == 1)
        #expect(Adventure.stop(id: "nope") == nil)
        #expect(Adventure.chapters.first?.continent == .europe)
    }

    @Test func earlyStopsHoldEasierFlagsThanLateStops() throws {
        let europe = try #require(Adventure.chapter(for: .europe))
        let first = try #require(europe.stops.first)
        let last = try #require(europe.stops.last)
        #expect(first.countryCodes.contains("FR") || first.countryCodes.contains("DE") || first.countryCodes.contains("GB"))
        #expect(!last.countryCodes.contains("FR"))
    }
}
