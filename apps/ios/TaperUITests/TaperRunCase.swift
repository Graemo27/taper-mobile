import XCTest

/// The vocabulary every run test drives the shipped binary with.
///
/// Shared because there is one app and one way to speak to it. Two copies of
/// "tap the row beginning with these words" is two places for a timeout to be
/// tuned, and the second copy is the one nobody updates.
///
/// Everything here goes through the labels a user reads and VoiceOver speaks.
/// No test-only hooks: a run that needs the harness to reach a screen has not
/// proven the screen is reachable.
class TaperRunCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The gate records its answer, so without this the second test in a run
        // takes a different path from the first. It clears the record; it does
        // not supply one, so every test below still passes the gate for real.
        // Both clear device state and supply none. The gate's answer would
        // otherwise make the second test in a run take a different path from
        // the first; the session would otherwise be one whose user
        // `supabase db reset` removed, which fails every write with a foreign
        // key and reports it as a connection problem.
        app.launchArguments = ["-TaperForgetAge", "-TaperForgetSession"]
        app.launch()
        passTheAgeGate()
    }

    /// Waits for onboarding, and names whatever arrived instead.
    ///
    /// The app now looks for an existing plan before drawing anything, so there
    /// are three ways to leave that check and only one of them is this suite's
    /// starting point. Asserting the *absence* of the error screen was not
    /// enough: it also passes while the lookup is still running, and it passes
    /// when a plan already exists and onboarding is skipped entirely.
    ///
    /// Both wrong destinations are named here rather than left for the first
    /// real assertion to report as "the question never appeared", which is true

    /// Answers the age gate as an adult. Every test needs it, because it is now
    /// the first thing the app shows.
    func passTheAgeGate() {
        let month = app.textFields["Month"]
        XCTAssertTrue(month.waitForExistence(timeout: 5), "The age gate did not appear")
        month.tap()
        month.typeText("01")
        app.textFields["Day"].typeText("01")
        app.textFields["Year"].typeText("1990")
        tapCTA("I'm 18 or older")
    }

    // MARK: - Walking

    /// Answers everything up to the readiness question, which is where the run
    /// forks. Kept in one place so a test says only what makes it different.
    func walkToReadiness() {
        expectQuestion("What are you quitting?")
        tapOption("Pouches")
        tapCTA("Continue")

        expectQuestion("What strength, per piece?")
        tapOption("3 mg")
        tapCTA("Continue")

        // The stepper opens on six, which is the answer this run gives.
        expectQuestion("How much do you use?")
        tapCTA("Continue")

        expectQuestion("How soon after waking is your first one?")
        tapOption("Within 30 minutes")
        tapCTA("Continue")

        expectQuestion("Do you still use when you're sick in bed?")
        tapOption("Yep")
        tapCTA("Continue")

        expectQuestion("What will you taper with?")
        tapOption("Patch")
        tapOption("Lozenge")
        tapCTA("Continue")

        // O6 asks nothing, so it has its own CTA and no Continue.
        expectStatic("Your starting line: 18 mg a day.")
        tapCTA("Build my plan")

        expectQuestion("When do you reach for one most?")
        tapCTA("Continue")

        expectQuestion("What have you tried before?")
        tapOption("Cold turkey")
        tapCTA("Continue")

        expectQuestion("Want to pick a quit date?")
    }

    // MARK: - Driving

    /// Taps a row by the words it starts with.
    ///
    /// A prefix rather than the whole label, because a row with a subtitle
    /// speaks both lines — "Patch, 14 mg, 24 hours · the steady floor" — and
    /// matching the lot would pin the test to copy it is not about. It is also
    /// how someone listening picks the row out.
    func tapOption(
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = option(label)
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "No option beginning \"\(label)\"", file: file, line: line
        )
        row.tap()
    }

    /// A row, by the words it starts with. Shared with the assertions rather
    /// than only tapped, so a test can ask whether a row is still chosen.
    func option(_ label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", label))
            .firstMatch
    }

    func tapCTA(
        _ title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons[title]
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "No button reading \"\(title)\"", file: file, line: line
        )
        XCTAssertTrue(
            button.isEnabled,
            "\"\(title)\" was there but disabled", file: file, line: line
        )
        button.tap()
    }

    func expectQuestion(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 5),
            "Expected the screen asking \"\(text)\"", file: file, line: line
        )
    }

    /// Asserts a screen the run should have walked past never arrives.
    ///
    /// Waits rather than reading `exists` once. A skip that stopped working
    /// shows the screen a beat later, after the push animation — and a bare
    /// `exists` at the moment of the tap is checked before it could appear,
    /// which passes for a reason that has nothing to do with the routing.
    func expectNever(
        _ text: String,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.staticTexts[text].waitForExistence(timeout: 2),
            message, file: file, line: line
        )
    }

    func expectStatic(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts[text].waitForExistence(timeout: 5),
            "Expected to read \"\(text)\"", file: file, line: line
        )
    }
}
