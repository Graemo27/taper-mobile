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
final class OnboardingRunTests: TaperRunCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        requireOnboarding()
    }

    /// and sends the reader to the wrong file.
    private func requireOnboarding() {
        if app.staticTexts["What are you quitting?"].waitForExistence(timeout: 10) { return }

        if app.staticTexts["Can't reach your plan."].exists {
            XCTFail(
                "The app could not reach a backend, so onboarding was never shown. "
                    + "This suite needs one running — `supabase start`."
            )
        } else if app.staticTexts["That's the plan."].exists {
            XCTFail(
                "This device already has a saved plan, so onboarding was skipped. "
                    + "Clear it with `supabase db reset --local`."
            )
        } else {
            XCTFail("Onboarding did not appear, and no state on screen explains why.")
        }
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
        // Waited for, not read once. The cap sits inside the scroll view and
        // the CTA is pinned outside it, so the two are not guaranteed to land
        // in the accessibility tree on the same pass — and a check that fails
        // on that would be reporting the harness, not the app.
        XCTAssertTrue(
            app.buttons["Start tracking"].waitForExistence(timeout: 5),
            "The plan screen offered no way to continue"
        )
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
        XCTAssertTrue(cap.waitForExistence(timeout: 5), "The plan screen showed no cap")
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
        // Arriving is not the thing worth checking. One answers object is
        // shared by the whole run, and going back is exactly where a reset
        // would hide: the screen looks right, the choice is gone, and nothing
        // says so until Continue turns out to be dead.
        XCTAssertTrue(
            option("Pouches").isSelected,
            "Back reached the right screen with the answer given there cleared"
        )
    }

}
