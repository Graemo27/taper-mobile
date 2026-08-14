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
    func testSaveToTodayStatesAndServingReset() {
        var app = launchFood("loaded", save: "succeeds")
        app.buttons["food.servings.increment"].tap()
        app.buttons["food.save-button"].tap()
        XCTAssertTrue(app.buttons["Saved to today"].waitForExistence(timeout: 3))

        app.buttons["food.servings.increment"].tap()
        XCTAssertTrue(app.buttons["Save to today"].exists)
        app.buttons["food.save-button"].tap()
        XCTAssertTrue(app.buttons["Saved to today"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save to today"].waitForExistence(timeout: 3))

        app.terminate()
        app = launchFood("loaded", save: "fails")
        app.buttons["food.save-button"].tap()
        XCTAssertTrue(app.buttons["Try saving again"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Your entry was not saved. Try again in a moment."].exists)
    }

    @MainActor
    func testFavouriteIsSharedAndFailedWriteRollsBack() {
        var app = launchSearch("results", favourite: "off")
        app.buttons["search.result.101"].tap()
        app.buttons["Add to favourites"].tap()
        XCTAssertTrue(app.buttons["Remove from favourites"].waitForExistence(timeout: 3))
        app.buttons["Back to search"].tap()
        XCTAssertTrue(app.buttons["search.result.101"].label.contains("favourite"))

        app.terminate()
        app = launchFood("loaded", favourite: "fails")
        app.buttons["Add to favourites"].tap()
        XCTAssertTrue(app.buttons["Add to favourites"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testRecentFoodsOpenByIDAndRefreshOnReturn() {
        let app = launchSearch("idle", recent: "refreshes")
        XCTAssertTrue(app.buttons["search.recent.101"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1 medium"].exists)

        app.buttons["search.recent.101"].tap()
        XCTAssertTrue(app.otherElements["food.detail.101"].waitForExistence(timeout: 3))
        app.buttons["Back to search"].tap()

        XCTAssertTrue(app.staticTexts["2 medium"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(_ fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPJournalFixture", fixture]
        app.launch()
        return app
    }

    @MainActor
    private func launchSearch(
        _ fixture: String, favourite: String? = nil, recent: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPSearchFixture", fixture]
        if let favourite { app.launchArguments += ["-FPFavouriteFixture", favourite] }
        if let recent { app.launchArguments += ["-FPRecentFixture", recent] }
        app.launch()
        return app
    }

    @MainActor
    private func launchFood(_ fixture: String, save: String? = nil, favourite: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FPFoodFixture", fixture]
        if let save { app.launchArguments += ["-FPSaveFixture", save] }
        if let favourite { app.launchArguments += ["-FPFavouriteFixture", favourite] }
        app.launch()
        return app
    }
}
