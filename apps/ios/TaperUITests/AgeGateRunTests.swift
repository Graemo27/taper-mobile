import XCTest

/// Drives L0 in the shipped binary.
///
/// The unit suite proves the age arithmetic and knows nothing about whether the
/// gate is actually in front of anything. That is the part worth driving: a
/// gate that computes the right answer and does not block is indistinguishable
/// from a working one until someone looks.
final class AgeGateRunTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-TaperForgetAge"]
        app.launch()
    }

    func testTheGateStandsInFrontOfOnboarding() throws {
        XCTAssertTrue(
            app.staticTexts["This app tracks nicotine."].waitForExistence(timeout: 5),
            "The app opened somewhere other than the age gate"
        )
        XCTAssertFalse(
            app.staticTexts["What are you quitting?"].waitForExistence(timeout: 2),
            "Onboarding was reachable without answering the gate"
        )
        XCTAssertFalse(
            app.buttons["I'm 18 or older"].isEnabled,
            "The gate could be passed without entering a birthdate"
        )
    }

    func testAnUnderageBirthdateIsRefusedRatherThanAdmitted() throws {
        enterBirthdate("01", "01", "2015")

        XCTAssertTrue(
            app.staticTexts["You need to be 18 to use Taper."].waitForExistence(timeout: 5),
            "An underage birthdate drew no refusal"
        )
        XCTAssertFalse(
            app.buttons["I'm 18 or older"].isEnabled,
            "An underage birthdate could still pass the gate"
        )
    }

    func testTheAnswerSurvivesARelaunch() throws {
        // The only claim on this screen a unit test cannot make. Asking an
        // adult to prove their age at every launch is the kind of thing that
        // looks fine in a single session and is intolerable in use.
        enterBirthdate("01", "01", "1990")
        app.buttons["I'm 18 or older"].tap()
        XCTAssertTrue(
            app.staticTexts["This app tracks nicotine."].waitForNonExistence(timeout: 5),
            "The gate stayed up after being answered"
        )
        expectStillRunning("after the gate was answered")

        // Relaunched without the reset, which is what tapping the icon does.
        app.launchArguments = []
        app.launch()

        // Asserts the gate is gone, not that onboarding is present. What comes
        // after the gate depends on whether this device already has a plan,
        // which is nothing to do with the claim being made here — coupling the
        // two made this fail for a reason its name does not mention.
        XCTAssertTrue(
            app.staticTexts["This app tracks nicotine."].waitForNonExistence(timeout: 5),
            "The gate asked again after it had already been answered"
        )
        expectStillRunning("after relaunching")
    }

    /// Absence of the gate is not the same as the gate having been passed.
    ///
    /// A crashed app has no gate text on screen either, so every assertion
    /// above is satisfied by the worst outcome available. There is no stable
    /// element to assert instead — what follows the gate depends on whether
    /// this device has a plan — so the check is that the app is still there.
    private func expectStillRunning(_ moment: String, line: UInt = #line) {
        XCTAssertEqual(
            app.state, .runningForeground,
            "The app was not running \(moment) — an absent gate can just mean a dead app",
            line: line
        )
    }

    private func enterBirthdate(_ month: String, _ day: String, _ year: String) {
        let field = app.textFields["Month"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The age gate did not appear")
        field.tap()
        field.typeText(month)
        app.textFields["Day"].typeText(day)
        app.textFields["Year"].typeText(year)
    }
}
