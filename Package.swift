// swift-tools-version: 6.0
import PackageDescription

// `FlagQuizCore` is the app's platform-independent game logic (quiz generation, sessions, adventure
// progression, daily challenge). It is a package so it builds and tests anywhere; the SwiftUI app in
// `App/` depends on it.
let package = Package(
    name: "FlagQuiz",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FlagQuizCore", targets: ["FlagQuizCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/AmrElsehemy/gametime-ios.git", branch: "master"),
        .package(url: "https://github.com/AmrElsehemy/geographica-kit.git", branch: "master")
    ],
    targets: [
        .target(
            name: "FlagQuizCore",
            dependencies: [
                .product(name: "GameTimeCore", package: "gametime-ios"),
                .product(name: "GameTimeServices", package: "gametime-ios"),
                .product(name: "GameTimeCommerce", package: "gametime-ios"),
                .product(name: "GeographicaCore", package: "geographica-kit"),
                .product(name: "GeographicaFlags", package: "geographica-kit")
            ]
        ),
        .testTarget(
            name: "FlagQuizCoreTests",
            dependencies: [
                "FlagQuizCore",
                .product(name: "GameTimeCore", package: "gametime-ios"),
                .product(name: "GameTimeCommerce", package: "gametime-ios"),
                .product(name: "GameTimeServices", package: "gametime-ios"),
                .product(name: "GameTimeTesting", package: "gametime-ios")
            ]
        )
    ]
)
