import XCTest

/// Walks the onboarding run in the shipped binary.
///
/// The unit suite reaches every model behind these screens and no view in
/// front of them, so until now twelve built screens had been checked only by
/// someone looking at them once. Two defects already merged past that gap: a
/// rail segment drawn as live when it was not, and a placeholder whose doc
/// comment was updated while the sentence on screen was left describing the
/// old behaviour. Neither is visible from a model test, and neither is visible
/// in a diff.
///
/// Everything here is driven by the labels a user reads and VoiceOver speaks.
/// No test-only hooks: a run that needs the harness to reach a screen has not
/// proven the screen is reachable.
final class OnboardingRunTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - The whole run

    func testTheRunReachesAPlanBuiltFromWhatWasAnswered() throws {
        walkToReadiness()
        tapOption("Set a quit date now")
        tapCTA("Continue")

        expectQuestion("Pick your quit date.")
        // No date is chosen here. The screen settles on one when it appears,
        // and a run that cannot continue without a tap would prove that had
        // stopped happening.
        tapCTA("Continue")

        expectQuestion("Here's your plan.")

        // 18 mg is 3 mg a pouch times the six the amount screen opens on, so it
        // can only be right if the strength and the count both reached the
        // planner and the planner reached the screen. A pipeline broken
        // anywhere shows a different number or none.
        let cap = app.descendants(matching: .any)["plan.cap"]
        XCTAssertTrue(cap.waitForExistence(timeout: 5), "The plan screen showed no cap")
        XCTAssertTrue(
            cap.label.contains("18 mg a day"),
            "Expected a cap of 18 mg a day, read \"\(cap.label)\""
        )
        XCTAssertTrue(
            cap.label.contains("days to go"),
            "A dated run should count down, read \"\(cap.label)\""
        )
        XCTAssertTrue(app.buttons["Start tracking"].exists)
    }

    // MARK: - The branches

    func testAReduceFirstRunIsNeverAskedForADate() throws {
        // The one branch in the run with a routing consequence. A skip is
        // invisible from outside — nothing renders and nothing errors — so the
        // only place it can be caught is a run that walks past it.
        walkToReadiness()
        tapOption("Reduce first — date later")
        tapCTA("Continue")

        // Asserted before the destination, deliberately. Checking only that we
        // landed on the plan reports a routing failure as "the plan screen
        // never appeared", which is true and names the wrong thing — the
        // failure a reader has to diagnose should be the one that happened.
        expectNever("Pick your quit date.", "A run that declined a date was asked for one anyway")
        expectQuestion("Here's your plan.")

        let cap = app.descendants(matching: .any)["plan.cap"]
        XCTAssertTrue(cap.waitForExistence(timeout: 5))
        XCTAssertFalse(
            cap.label.contains("days to go"),
            "A run holding where it is was given a countdown, read \"\(cap.label)\""
        )
    }

    func testASourceWithNoPrintedStrengthIsNotAskedForOne() throws {
        // A cigarette has no per-piece figure to give. Asking anyway would make
        // the user invent the number the plan is then built on.
        expectQuestion("What are you quitting?")
        tapOption("Cigarettes")
        tapCTA("Continue")

        expectNever(
            "What strength, per piece?",
            "A cigarettes-only run was asked for a printed strength"
        )
        expectQuestion("How much do you use?")
    }

    func testBackReturnsToTheAnswerJustGiven() throws {
        // Assert the exit from a state, not only the entry. Every screen after
        // the first offers a way back, and nothing else checks that it lands
        // where the user expects.
        expectQuestion("What are you quitting?")
        tapOption("Pouches")
        tapCTA("Continue")

        expectQuestion("What strength, per piece?")
        app.buttons["Back"].tap()

        expectQuestion("What are you quitting?")
    }

    // MARK: - Walking

    /// Answers everything up to the readiness question, which is where the run
    /// forks. Kept in one place so a test says only what makes it different.
    private func walkToReadiness() {
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
    private func tapOption(
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", label))
            .firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "No option beginning \"\(label)\"", file: file, line: line
        )
        row.tap()
    }

    private func tapCTA(
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

    private func expectQuestion(
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
    private func expectNever(
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

    private func expectStatic(
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
