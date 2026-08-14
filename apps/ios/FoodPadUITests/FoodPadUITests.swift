import XCTest

final class FoodPadUITests: XCTestCase {
    @MainActor
    func testJournalShellIsAddressable() {
        let app = launch("empty")

        XCTAssertTrue(app.otherElements["journal.empty-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["journal.add-button"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Journal empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testEveryJournalStateRenders() {
        var app = launch("loading")
        XCTAssertTrue(app.otherElements["journal.loading-state"].waitForExistence(timeout: 3))

        app.terminate()
        app = launch("populated")
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple"].exists)
        XCTAssertTrue(app.staticTexts["2 things"].exists)

        app.terminate()
        app = launch("failed-with-rows")
        XCTAssertTrue(app.otherElements["journal.failure-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple"].exists)
        XCTAssertTrue(app.buttons["journal.retry-button"].exists)

        app.terminate()
        app = launch("failed")
        XCTAssertTrue(app.staticTexts["Could not open your journal"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPJournalFixture", fixture]
        app.launch()
        return app
    }
}
