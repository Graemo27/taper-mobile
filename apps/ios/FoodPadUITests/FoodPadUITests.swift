import XCTest

final class FoodPadUITests: XCTestCase {
    @MainActor
    func testJournalShellIsAddressable() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.otherElements["journal.empty-state"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["journal.add-button"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Journal empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
