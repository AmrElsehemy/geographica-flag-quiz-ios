import GeographicaCore
import GeographicaFlags

/// One stop on the world map: a handful of flags from a single continent.
public struct Stop: Hashable, Identifiable, Sendable {
    public let id: String
    public let continent: Continent
    /// 1-based position within its chapter.
    public let number: Int
    public let countryCodes: [String]

    public init(id: String, continent: Continent, number: Int, countryCodes: [String]) {
        self.id = id
        self.continent = continent
        self.number = number
        self.countryCodes = countryCodes
    }
}

/// A continent, played as a chapter of stops ordered from familiar flags to obscure ones.
public struct Chapter: Hashable, Identifiable, Sendable {
    public var id: String { continent.rawValue }
    public let continent: Continent
    public let stops: [Stop]

    public var maxStars: Int { stops.count * Adventure.maxStarsPerStop }
}

public enum Adventure {
    public static let flagsPerStop = 5
    public static let maxStarsPerStop = 3
    /// Share of the previous chapter's stars needed to open the next chapter.
    public static let unlockFraction = 0.5

    public static let chapterOrder: [Continent] = [
        .europe, .northAmerica, .southAmerica, .asia, .africa, .oceania
    ]

    public static let chapters: [Chapter] = chapterOrder.map(makeChapter)

    public static func chapter(for continent: Continent) -> Chapter? {
        chapters.first { $0.continent == continent }
    }

    public static func stop(id: String) -> Stop? {
        chapters.lazy.flatMap(\.stops).first { $0.id == id }
    }

    /// Stars needed in `chapter` before the following chapter opens.
    public static func starsToUnlockNext(after chapter: Chapter) -> Int {
        Int((Double(chapter.maxStars) * unlockFraction).rounded(.up))
    }

    private static func makeChapter(_ continent: Continent) -> Chapter {
        let ordered = CountryCatalog.countries(in: continent).sorted {
            let (a, b) = (FlagCatalog.difficulty(of: $0), FlagCatalog.difficulty(of: $1))
            return a == b ? $0.name < $1.name : a < b
        }
        var groups = stride(from: 0, to: ordered.count, by: flagsPerStop).map {
            Array(ordered[$0..<min($0 + flagsPerStop, ordered.count)]).map(\.iso2)
        }
        // Avoid a tiny final stop: fold a short remainder into the previous one.
        if groups.count > 1, let last = groups.last, last.count < 3 {
            groups.removeLast()
            groups[groups.count - 1] += last
        }
        let stops = groups.enumerated().map { offset, codes in
            Stop(id: "\(continent.rawValue)-\(offset + 1)", continent: continent, number: offset + 1, countryCodes: codes)
        }
        return Chapter(continent: continent, stops: stops)
    }
}
