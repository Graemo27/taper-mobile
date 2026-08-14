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
    func testSearchResultsNavigateWithTheSelectedFood() {
        let app = launchSearch("results")

        XCTAssertTrue(app.textFields["search.field"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["search.results-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["2 matches"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Search results"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["search.result.101"].tap()
        XCTAssertTrue(app.otherElements["food.detail.101"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Apple"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["food.nutrition"].exists)

        app.buttons["food.servings.increment"].tap()
        XCTAssertTrue(app.staticTexts["2 servings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["189"].exists)
    }

    @MainActor
    func testEverySearchStateRenders() {
        var app = launchSearch("loading")
        XCTAssertTrue(app.otherElements["search.loading-state"].waitForExistence(timeout: 3))

        app.terminate()
        app = launchSearch("empty")
        XCTAssertTrue(app.otherElements["search.empty-state"].waitForExistence(timeout: 3))

        app.terminate()
        app = launchSearch("failed")
        XCTAssertTrue(app.otherElements["search.failure-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["search.retry-button"].exists)
    }

    @MainActor
    func testFoodDetailLoadsByID() {
        let app = launchFood("loaded")

        XCTAssertTrue(app.otherElements["food.detail.101"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["High in"].exists)
        XCTAssertTrue(app.staticTexts["Nutrition"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Food detail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testEveryFoodLookupStateRenders() {
        var app = launchFood("loading")
        XCTAssertTrue(app.otherElements["food.loading-state"].waitForExistence(timeout: 3))

        app.terminate()
        app = launchFood("missing")
        XCTAssertTrue(app.otherElements["food.missing-state"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["food.retry-button"].exists)

        app.terminate()
        app = launchFood("failed")
        XCTAssertTrue(app.otherElements["food.failure-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["food.retry-button"].exists)
    }

    @MainActor
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPJournalFixture", fixture]
        app.launch()
        return app
    }

    @MainActor
    private func launchSearch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPSearchFixture", fixture]
        app.launch()
        return app
    }

    @MainActor
    private func launchFood(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPFoodFixture", fixture]
        app.launch()
        return app
    }
}
