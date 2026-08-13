import XCTest

final class FoodPadUITests: XCTestCase {
    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["bootstrap.screen"].waitForExistence(timeout: 3))
    }
}
