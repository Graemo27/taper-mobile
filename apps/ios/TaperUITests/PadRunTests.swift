import XCTest

/// Drives the whole app in the shipped binary: onboarding through to a tap
/// that is logged.
///
/// This is the run nothing else covers. The unit suite reaches every model,
/// the live suite reaches every table, and neither of them presses a button —
/// so until now the pad had been drawn, driven by screenshot and tested by
/// model, with nothing checking that its keys were connected to any of it.
///
/// It needs a local backend and a database with no plan on it, like the rest of
/// the run suite: `supabase start`, then `supabase db reset --local`.
///
/// **It leaves a plan behind**, and it refuses to start with one — like the
/// other run suites, and for a sharper reason: every assertion here is about
/// the plan this run builds, so an inherited one would either fail for
/// unrelated data or pass without the handoff ever happening.
///
/// That makes the whole suite single-shot against a given database. The run
/// suites happen to work today because `OnboardingRunTests` sorts before
/// `PadRunTests`, which is an ordering nobody declared — worth knowing before
/// a class is renamed.
final class PadRunTests: TaperRunCase {
    /// The pouch key onboarding seeds from a 3 mg answer.
    private let pouches = "Pouches, 3 milligrams"

    /// Onboarding, all the way to a saved plan.
    ///
    /// Onboarding is *required*, not preferred. Every assertion below is about
    /// the plan this run builds — a 3 mg pouch, an 18 mg cap, a 14 mg patch —
    /// and accepting whatever plan happened to be on the device would let the
    /// suite pass without the onboarding-to-pad handoff ever happening, which
    /// is the one thing it exists to check.
    private func reachTheTabs() {
        guard app.staticTexts["What are you quitting?"].waitForExistence(timeout: 10) else {
            if app.buttons["tab.log"].exists {
                XCTFail(
                    "This device already has a saved plan, so onboarding was skipped — and the "
                        + "assertions here are about the plan this run builds. "
                        + "Clear it with `supabase db reset --local`."
                )
            } else if app.staticTexts["Can't reach your plan."].exists {
                XCTFail(
                    "The app could not reach a backend, so onboarding was never shown. "
                        + "This suite needs one running — `supabase start`."
                )
            } else {
                XCTFail("Onboarding did not appear, and no state on screen explains why.")
            }
            return
        }

        walkToReadiness()
        tapOption("Set a quit date now")
        tapCTA("Continue")
        expectQuestion("Pick your quit date.")
        tapCTA("Continue")

        expectQuestion("Here's your plan.")
        tapCTA("Start tracking")

        // Named rather than left as "the tabs never appeared", which is true
        // and sends the reader to the wrong file. The save is the step most
        // likely to fail here and it fails quietly, on screen, in words that
        // blame the connection.
        if !app.buttons["tab.log"].waitForExistence(timeout: 10) {
            if app.staticTexts["Couldn't save your plan. Check your connection and try again."].exists {
                XCTFail(
                    "The plan could not be saved. The likeliest cause is a session whose user "
                        + "`supabase db reset` removed — every write then fails a foreign key. "
                        + "`-TaperForgetSession` is meant to prevent exactly that."
                )
            } else {
                let shown = app.staticTexts.allElementsBoundByIndex.prefix(8).map { $0.label }
                XCTFail("Saving the plan did not land on the tabs. On screen: \(shown)")
            }
        }
    }

    /// The pad, reached the way a user reaches it.
    private func openTheLog() {
        reachTheTabs()
        app.buttons["tab.log"].tap()
        XCTAssertTrue(
            app.buttons[pouches].waitForExistence(timeout: 10),
            "The log tab showed no key for the pouches this run said it was quitting"
        )
    }

    // MARK: - The run

    func testOnboardingSeedsAPadYouCanReach() throws {
        // The seam between two PRs that were only ever tested apart: onboarding
        // writes the pad, and the log tab reads it. Both halves have passed
        // against fakes and against Postgres, and neither has ever been asked
        // to hand off to the other in the shipped binary.
        openTheLog()

        // The treatment answers too, at the strengths the plan committed to.
        // 14 mg, not 21: the planner sizes the patch to intake, and 18 mg a
        // day sits in the 10–20 band. Reading 21 here would mean the pad had
        // been seeded from something other than this run's own plan.
        XCTAssertTrue(
            app.buttons["Patch, 14 milligrams"].exists,
            "The pad has no 14 mg patch key, though the run chose a patch at 18 mg a day"
        )
        XCTAssertTrue(
            app.staticTexts["0 of 18 mg today"].waitForExistence(timeout: 5),
            "The pad did not show an untouched day against the plan's cap"
        )
    }

    func testHomeShowsTodayAndItsButtonReachesThePad() throws {
        // Home reads the day now, which it deliberately did not before — every
        // other figure on that screen comes off the plan and is known at
        // launch. The card is the first thing there that waits on a request,
        // so the check is that it arrives at all rather than sitting on a dash.
        reachTheTabs()

        XCTAssertTrue(
            app.staticTexts["Today so far"].waitForExistence(timeout: 10),
            "Home never drew the tracking card"
        )
        XCTAssertTrue(
            app.staticTexts["Today so far, 0 of 18 milligrams"].waitForExistence(timeout: 10),
            "The card never resolved to a real day — it is still showing a dash, which is what "
                + "it draws when the read has not come back"
        )

        // The card's whole job: it is the door to the pad, and until L7 exists
        // it is the only button on it.
        app.buttons["home.checkIn"].tap()
        XCTAssertTrue(
            app.buttons[pouches].waitForExistence(timeout: 10),
            "\"Check in on the pad\" did not land on the pad"
        )
    }

    func testTappingAKeyMovesTheDayItWouldLeaveBehind() throws {
        // The gap named in the PR that made keys tappable: `simctl` cannot
        // inject a tap and nothing could reach this screen, so the button was
        // connected to the record by inspection only.
        openTheLog()

        app.buttons[pouches].tap()

        XCTAssertTrue(
            app.buttons["Check in · 3 mg"].waitForExistence(timeout: 5),
            "A tap on a 3 mg key did not reach the button that logs it"
        )

        // Twice is three sixes, and the readout is what proves the count is
        // being kept rather than the selection being replaced.
        app.buttons[pouches].tap()
        XCTAssertTrue(
            app.buttons["Check in · 6 mg"].waitForExistence(timeout: 5),
            "A second tap on the same key did not count one more of it"
        )
    }

    func testClearingPutsThePadBackToResting() throws {
        openTheLog()
        app.buttons[pouches].tap()
        XCTAssertTrue(app.buttons["Check in · 3 mg"].waitForExistence(timeout: 5))

        app.buttons["Clear"].tap()

        XCTAssertTrue(
            app.buttons["Check in"].waitForExistence(timeout: 5),
            "Clearing left the pad still holding a selection"
        )
    }

    func testCheckingInWritesTheTapAndMovesTheDay() throws {
        // The whole point of the app, end to end for the first time: answers
        // become a plan, the plan seeds a pad, a key is tapped, and the tap
        // reaches the database — which the readout can only report by having
        // been told so.
        openTheLog()
        app.buttons[pouches].tap()
        tapCTA("Check in · 3 mg")

        XCTAssertTrue(
            app.staticTexts["3 of 18 mg today"].waitForExistence(timeout: 10),
            "The day did not move after a check-in"
        )
        XCTAssertTrue(
            app.buttons["Check in"].waitForExistence(timeout: 5),
            "The selection survived a write that succeeded"
        )
    }
}
