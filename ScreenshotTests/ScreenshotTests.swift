import XCTest

/// Captures the App Store screenshots from the real app. Each test launches the app in a fixed
/// debug "demo state" (see `App/DemoMode.swift`), waits for the screen to appear, and saves a PNG
/// to `$SCREENSHOT_DIR` (set by `Scripts/capture-screenshots.sh`). The shots are also attached to the
/// test result, so they can be pulled from the `.xcresult` too.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func test01_NameThatFlag() {
        capture(scene: "quiz-nepal", name: "01-name-that-flag", appears: "A national flag")
    }

    func test02_SpotTheLookalikes() {
        capture(scene: "quiz-lookalike", name: "02-spot-the-lookalikes", appears: "A national flag")
    }

    func test03_UnlockTheWorld() {
        capture(scene: "home", name: "03-unlock-the-world", appears: "Daily Challenge")
    }

    func test04_DailyChallenge() {
        capture(scene: "result-daily", name: "04-daily-challenge", appears: "Daily complete!")
    }

    func test05_ThreeStars() {
        capture(scene: "result-stars", name: "05-three-stars", appears: "Stop complete!")
    }

    func test06_LearnAsYouPlay() {
        capture(scene: "tutorial", name: "06-learn-as-you-play", appears: "Tap the country that matches the flag.")
    }

    // MARK: -

    private func capture(scene: String, name: String, appears label: String, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo-state", scene, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        let ready = app.descendants(matching: .any)[label].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "\(name): '\(label)' never appeared", file: file, line: line)

        // Let transitions, shadows and the flag's entrance animation finish.
        Thread.sleep(forTimeInterval: 1.5)

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: url.appendingPathComponent("\(name).png"))
            } catch {
                XCTFail("\(name): could not write PNG: \(error)", file: file, line: line)
            }
        }
        app.terminate()
    }
}
