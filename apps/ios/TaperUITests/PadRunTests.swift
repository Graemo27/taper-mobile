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

    func testAPendingTapOnThePadDoesNotReachHome() throws {
        // The selection survives a tab switch on purpose — it is a count
        // somebody is still tapping out. Home's card is a statement about what
        // has happened, so a tap nobody has committed must not appear in it:
        // the bar would draw milligrams the figure beside it does not count,
        // and a big enough selection would turn that figure red for a dose
        // never taken.
        //
        // Tapped past the cap on purpose. A single 3 mg tap leaks invisibly —
        // home's figure counts what is logged either way, so only the bar and
        // the red would differ and neither is a thing this suite can read. Over
        // the 18 mg cap the leak has to say itself out loud.
        openTheLog()
        for _ in 1...7 { app.buttons[pouches].tap() }
        XCTAssertTrue(
            app.buttons["Check in · 21 mg"].waitForExistence(timeout: 5),
            "The pad did not take seven taps, so there was no pending selection to carry home"
        )

        app.buttons["tab.home"].tap()
        XCTAssertTrue(
            app.staticTexts["Today so far, 0 of 18 milligrams"].waitForExistence(timeout: 10),
            "An uncommitted tap on the pad reached home's card — the label would read "
                + "\"over today's cap\" off 21 mg nobody has logged"
        )

        // Said outright rather than left to the exact-match semantics of the
        // assertion above. That one fails against the leak because the label
        // grows a suffix, which is true and is not obvious from reading it —
        // and the whole point of tapping past the cap was to make the leak
        // speak. This is the sentence it would say.
        expectNever(
            "Today so far, 0 of 18 milligrams, over today's cap",
            "Home called a day over its cap on 21 mg that only exist as a selection on the pad"
        )
    }

    func testACheckInCanBeTakenBackOffTheDay() throws {
        // `TodayRecord.remove(_:)` has been written, tested and unreachable
        // since #106 — no screen called it. This is the first run in which a
        // person can undo a mis-tap, which is the whole reason the list exists.
        openTheLog()
        app.buttons[pouches].tap()
        app.buttons["Check in · 3 mg"].tap()
        XCTAssertTrue(
            app.staticTexts["3 of 18 mg today"].waitForExistence(timeout: 10),
            "The check-in did not land, so there was nothing to take back"
        )

        app.buttons["tab.home"].tap()
        app.buttons["home.seeHistory"].tap()
        XCTAssertTrue(
            app.staticTexts["Today so far, 3 of 18 milligrams"].waitForExistence(timeout: 10)
                || app.staticTexts["Today"].waitForExistence(timeout: 10),
            "The list never opened"
        )

        // The row, then the screen it opens, then the removal.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'today.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The day's list had no rows to open")
        // `isHittable` is not the question. A row with no hit shape reports
        // itself hittable and still swallows the tap, which is how this shipped
        // broken for exactly one run.
        XCTAssertTrue(row.isHittable, "the row button exists but cannot be tapped")
        row.tap()

        let remove = app.buttons["edit.remove"]
        if !remove.waitForExistence(timeout: 10) {
            let btns = app.buttons.allElementsBoundByIndex.prefix(12)
                .map { "\($0.identifier.isEmpty ? $0.label : $0.identifier)/hit=\($0.isHittable)" }
            XCTFail("Tapping a row did not open the check-in. Buttons: \(btns)")
            return
        }
        remove.tap()

        // Back on the list, with the row gone and the day given its mg back.
        XCTAssertTrue(
            app.staticTexts["0 check-ins · 0 of 18 mg"].waitForExistence(timeout: 10),
            "The check-in was not taken off the day"
        )
    }

    func testTheCardOpensTheDayAsAList() throws {
        // The card is the only door to this screen — the board's flows note
        // routes nothing else there — so the one path in is the one thing that
        // has to be driven rather than inspected.
        reachTheTabs()
        app.buttons["home.seeHistory"].tap()

        XCTAssertTrue(
            app.staticTexts["Today"].waitForExistence(timeout: 10),
            "\"See check-in history\" did not open the day's list"
        )

        // The bar stays, with home still lit. The board is explicit about it,
        // and it is the reason this is a push above the bar rather than a
        // screen of its own — somebody correcting a mis-tap here usually wants
        // the pad next.
        XCTAssertTrue(app.buttons["tab.log"].exists, "the tab bar went away under the list")

        app.buttons["today.back"].tap()
        XCTAssertTrue(
            app.staticTexts["Today so far"].waitForExistence(timeout: 5),
            "Back did not return to home"
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

    func testTheCatalogueOpensFromThePadAndGivesItBack() throws {
        // The pad has had no way onto it since it was drawn: keys arrived from
        // onboarding and nothing could add one. This is that door, and the way
        // back out of it — a search you cannot leave would strand somebody on
        // the one screen with no check-in button.
        openTheLog()
        app.buttons["pad.addTreatment"].tap()

        let field = app.textFields["search.field"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 5),
            "Tapping Add treatment did not open the catalogue search"
        )
        // The search replaces the keys rather than covering them, so the pad
        // it came from should be gone while it is up.
        XCTAssertFalse(
            app.buttons[pouches].exists,
            "The keys were still on screen underneath the search"
        )
        // What this list is, said where somebody is about to type. The backend
        // refuses anything but licensed NRT; a person looking for their pouches
        // should read why rather than conclude the app is broken.
        XCTAssertTrue(
            app.staticTexts.element(
                matching: NSPredicate(format: "label BEGINSWITH %@",
                                      "Licensed nicotine replacement only")
            ).exists,
            "The search did not say it is restricted to licensed nicotine replacement"
        )

        app.buttons["search.cancel"].tap()
        XCTAssertTrue(
            app.buttons[pouches].waitForExistence(timeout: 5),
            "Cancelling the search did not put the pad back"
        )
        XCTAssertFalse(field.exists, "The search field outlived its own cancel button")
    }
}
