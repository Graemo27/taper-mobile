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

    func testTheCravingButtonOpensTheScreenForOneAndCountsIt() throws {
        // The seam this suite exists for, one more time: L8 was drawn, tested
        // by model, and reachable from nothing. Every piece of it — the
        // suggestion off the pad, the write, the row landing on the day — had
        // passed with no user able to arrive at the screen.
        reachTheTabs()
        tapCTA("I'm craving right now")

        XCTAssertTrue(
            app.staticTexts["Let it crest."].waitForExistence(timeout: 10),
            "\"I'm craving right now\" did not open the craving screen"
        )

        // The one screen the board draws without the bar, because somebody
        // mid-craving is doing one thing.
        XCTAssertFalse(
            app.buttons["tab.log"].isHittable,
            "the tab bar came with the craving screen"
        )

        // This run tapers with a patch and a lozenge. A patch holds a floor and
        // is no answer to a moment, so the lozenge is the only thing here that
        // can be offered — and offering the patch is the mistake that would
        // look right on a screenshot.
        XCTAssertTrue(
            option("Take your lozenge").exists,
            "The screen did not offer the one fast-acting treatment on this run's pad"
        )
        expectNever(
            "Take your patch · 14 mg",
            "The screen offered a patch to somebody in the middle of a craving"
        )

        tapCTA("It passed — count it")

        // It writes, it closes, and the day it wrote onto is unchanged: an urge
        // is on the list and is not a check-in.
        XCTAssertTrue(
            app.staticTexts["Today so far, 0 of 18 milligrams"].waitForExistence(timeout: 10),
            "Counting a craving did not return home, or it counted against the cap"
        )
        app.buttons["home.seeHistory"].tap()
        XCTAssertTrue(
            app.staticTexts["Urge passed"].waitForExistence(timeout: 10),
            "The craving was counted but never reached the day's list"
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

    func testASearchResultBecomesAKeyOnThePad() throws {
        // The seam three PRs have built toward and none has crossed: the search
        // finds a licensed product, the form names it, the store writes it, and
        // the pad it was opened from shows it. Each half has passed alone.
        //
        // It searches the real catalogue through the local Edge Function, which
        // is the point — a fake would prove the wiring and not that a product
        // openFDA actually returns can become a key.
        openTheLog()
        app.buttons["pad.addTreatment"].tap()

        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the catalogue did not open")
        field.tap()
        // The keyboard is deliberately left up. Typing a brand and tapping a
        // result without dismissing anything is the ordinary way through this
        // screen, and it is the arrangement that was broken: the rows were
        // drawn in plain sight and refused the tap.
        field.typeText("nicorette")

        // Skipped, not failed, when the catalogue does not answer. The local
        // Edge Function runs without `OPENFDA_API_KEY`, which puts it on
        // openFDA's 1,000-a-day-per-IP allowance — shared with every other
        // thing leaving this machine. A red run that means "somebody else used
        // the quota" teaches people to ignore red runs, and this suite's worth
        // is that its failures are real.
        let result = app.buttons["search.result"].firstMatch
        guard result.waitForExistence(timeout: 20) else {
            throw XCTSkip(
                "openFDA returned nothing for 'nicorette', so the catalogue could not be "
                    + "reached. The seam this test covers was not exercised."
            )
        }
        result.tap()

        let name = app.textFields["newKey.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "picking a result opened no form")
        XCTAssertFalse(
            (name.value as? String ?? "").isEmpty,
            "the form opened without the product's name in it"
        )

        // The strength the pad will carry, read before saving so the assertion
        // afterwards is about this key rather than about a number we chose.
        let mg = app.staticTexts["newKey.mg"].label
        app.buttons["newKey.save"].tap()

        // Back on the pad, with the key on it — the search closes itself, so the
        // add tile returning is how we know we are looking at keys again.
        XCTAssertTrue(
            app.buttons["pad.addTreatment"].waitForExistence(timeout: 15),
            "saving left the search open"
        )
        let key = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "\(mg) milligrams")
        ).firstMatch
        XCTAssertTrue(
            key.waitForExistence(timeout: 10),
            "the key was written but the pad never showed it"
        )
    }

    func testSomethingElseBeingQuitCanBeAddedByHand() throws {
        // The gap this closes: the pad could only ever hold what onboarding
        // seeded, so anybody who picked up a second thing had nowhere to log
        // it — and a source that cannot be logged is a cap that silently lies.
        //
        // No catalogue is involved, which is why this run needs no network
        // beyond the database: what somebody is quitting is typed, never looked
        // up.
        openTheLog()
        app.buttons["pad.addSource"].tap()

        let cigarette = app.buttons["newSource.form.cigarettes"]
        XCTAssertTrue(cigarette.waitForExistence(timeout: 5), "the add tile opened nothing")
        XCTAssertFalse(
            app.textFields["search.field"].exists,
            "the hand-typed path offered a catalogue search"
        )
        cigarette.tap()

        // The ladder moves with the form, so the number is read after choosing.
        let mg = app.staticTexts["newSource.mg"].label
        app.buttons["newSource.save"].tap()

        XCTAssertTrue(
            app.buttons["pad.addSource"].waitForExistence(timeout: 15),
            "saving left the form open"
        )
        let key = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "\(mg) milligrams")
        ).firstMatch
        XCTAssertTrue(
            key.waitForExistence(timeout: 10),
            "the key was written but the pad never showed it"
        )
    }

    func testAPadTallerThanTheScreenCanStillBeCheckedInOn() throws {
        // The pad only ever held what onboarding seeded until the add tiles
        // landed. Since then it can grow past the screen — and with nothing
        // scrolling, the keys and the button the whole screen exists for went
        // off the bottom with no way back to them.
        openTheLog()

        // Enough to overrun the screen: three keys to a row, and roughly three
        // rows fit above the actions.
        for _ in 0..<11 {
            app.buttons["pad.addSource"].tap()
            let save = app.buttons["newSource.save"]
            XCTAssertTrue(save.waitForExistence(timeout: 5), "the source form did not open")
            save.tap()
            XCTAssertTrue(
                app.buttons["pad.addSource"].waitForExistence(timeout: 15),
                "saving left the form open"
            )
        }

        // Pinned, not scrolled to: the actions sit below the keys and stay
        // there, which is how the board draws a pad scrolled to its end.
        let checkIn = app.buttons["Check in"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5), "the check-in button is gone")
        XCTAssertTrue(
            checkIn.isHittable,
            "a pad taller than the screen pushed the check-in button out of reach"
        )

        // It overran at both ends, which is why this checks both. At eleven
        // added keys the unscrolled pad put the meter at y = -9 and the button
        // at y = 874 on an 874-point screen: the day's own readout above the
        // top of the display, and the way to log anything below the bottom.
        let meter = app.staticTexts.element(
            matching: NSPredicate(format: "label CONTAINS %@", "mg today")
        )
        XCTAssertTrue(meter.exists, "the cap readout is gone")
        XCTAssertTrue(
            meter.frame.minY > 0,
            "a pad taller than the screen pushed the day's readout off the top"
        )

        // And the end of the run is reachable by scrolling rather than lost.
        let end = app.staticTexts.element(
            matching: NSPredicate(format: "label BEGINSWITH %@", "That's the whole pad")
        )
        XCTAssertTrue(end.waitForExistence(timeout: 5), "the pad never said where it ended")

        // Scrolled *to*, not merely present. `waitForExistence` asks the
        // hierarchy, and a `ScrollView` keeps its off-screen content in there —
        // so the marker exists whether or not anything can reach it, and an
        // assertion on existence alone would pass on a pad that does not
        // scroll at all.
        var swipes = 0
        while !end.isHittable, swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(end.isHittable, "the end of the pad could not be scrolled to")
    }

    /// L3e's other half, driven: the pad is rearranged by hand and stays that
    /// way across a relaunch.
    ///
    /// Only a run can show this. The gesture arithmetic is unit-tested and the
    /// write is store-tested, but neither can say whether a drag on a real pad
    /// reaches either of them — and the whole feature is a finger on a key.
    func testAKeyCanBeDraggedToANewPlace() throws {
        openTheLog()

        // A second source, so there is an order to change. Typed rather than
        // searched: what somebody is quitting never comes from a catalogue.
        app.buttons["pad.addSource"].tap()
        let cigarette = app.buttons["newSource.form.cigarettes"]
        XCTAssertTrue(cigarette.waitForExistence(timeout: 5), "the add tile opened nothing")
        cigarette.tap()
        let addedMg = app.staticTexts["newSource.mg"].label
        app.buttons["newSource.save"].tap()

        let pouches = app.buttons[self.pouches]
        XCTAssertTrue(pouches.waitForExistence(timeout: 10), "the seeded key is missing")
        let addedLabel = "Cigarettes, \(addedMg) milligrams"
        let added = app.buttons[addedLabel]
        XCTAssertTrue(added.waitForExistence(timeout: 10), "the second source never landed")
        XCTAssertLessThan(
            pouches.frame.minX, added.frame.minX,
            "the fixture does not start in the order this test is about to change"
        )

        pouches.press(forDuration: 1.0)
        XCTAssertTrue(
            app.buttons["pad.doneEditing"].waitForExistence(timeout: 5),
            "a long press did not open edit mode"
        )

        // Onto the seat beside it, held long enough that the press is read as
        // a drag rather than a tap.
        pouches.press(forDuration: 0.6, thenDragTo: added)

        XCTAssertTrue(
            app.buttons[addedLabel].waitForExistence(timeout: 5),
            "the pad stopped drawing its keys"
        )
        XCTAssertLessThan(
            app.buttons[addedLabel].frame.minX,
            app.buttons[self.pouches].frame.minX,
            "the key did not move under the drag"
        )

        app.buttons["pad.doneEditing"].tap()

        // The point of the write. A rearrangement that only lived on screen
        // would look identical to a saved one until something re-read the pad,
        // and leaving the tab is what does that — `task(id:)` reloads on the
        // way back. A relaunch would prove more and cannot be used: this
        // harness launches with the session forgotten, so the app would come
        // back as a different anonymous person with no pad at all.
        app.buttons["tab.home"].tap()
        XCTAssertTrue(
            app.buttons["home.craving"].waitForExistence(timeout: 10),
            "home never appeared, so the pad was never left"
        )
        app.buttons["tab.log"].tap()

        XCTAssertTrue(
            app.buttons[addedLabel].waitForExistence(timeout: 10),
            "the pad did not come back"
        )
        XCTAssertLessThan(
            app.buttons[addedLabel].frame.minX,
            app.buttons[self.pouches].frame.minX,
            "the new order was not what the server sent back"
        )
    }

    func testAKeyCanBeTakenOffThePad() throws {
        // Until now every key was permanent. A mis-tapped "Add" stayed on the
        // pad for good, which is the thing that made this app not worth putting
        // on a phone.
        openTheLog()

        let pouches = app.buttons[self.pouches]
        XCTAssertTrue(pouches.waitForExistence(timeout: 10), "the seeded key is missing")
        pouches.press(forDuration: 1.0)

        XCTAssertTrue(
            app.buttons["pad.doneEditing"].waitForExistence(timeout: 5),
            "a long press did not open edit mode"
        )
        // The meter is a statement about a day being logged, and nothing here
        // logs anything.
        XCTAssertFalse(
            app.buttons["Check in"].exists,
            "the check-in button stayed up while the pad was being edited"
        )

        let badge = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pad.remove.")
        ).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5), "no key offered a way off the pad")
        // The badge says "Remove <key label>", so the key it is for is the
        // rest of the sentence.
        let removed = badge.label.replacingOccurrences(of: "Remove ", with: "")
        let key = app.buttons.matching(NSPredicate(format: "label == %@", removed)).firstMatch
        XCTAssertTrue(key.exists, "the badge named a key that is not on the pad")
        badge.tap()

        // Waited for, because Done refuses to close over a delete in flight —
        // a pad put back with a key on it that is about to vanish reads as the
        // tap having done nothing.
        let gone = expectation(for: NSPredicate(format: "exists == false"),
                               evaluatedWith: key)
        wait(for: [gone], timeout: 15)

        // Gone from the server rather than just from the screen: leaving edit
        // mode re-reads nothing, so a key still here after Done was never
        // really deleted.
        app.buttons["pad.doneEditing"].tap()
        XCTAssertTrue(
            app.buttons["Check in"].waitForExistence(timeout: 10),
            "Done did not put the pad back"
        )
        // "Check in" and not "Check in · 3 mg": a long press to edit must not
        // also queue a tap. The gesture is simultaneous with the button's, so
        // without the guard the press that opened the mode also selected the
        // key it was pressed on, and Done handed back a pad with a check-in
        // waiting on it that nobody asked for.
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Check in ·"))
                .firstMatch.exists,
            "the long press that opened editing also queued a check-in"
        )
        XCTAssertFalse(
            app.buttons.matching(NSPredicate(format: "label == %@", removed)).firstMatch.exists,
            "the key came back after it was removed"
        )
    }
}

extension PadRunTests {
    func testTheLabelCanBeReadAndLoggedFromTheCatalogue() throws {
        // L5 end to end: the search finds a product, the info button opens its
        // label, a strength and count become a check-in, and the day shows the
        // row — on the treatment ledger, so the cap does not move.
        openTheLog()
        app.buttons["pad.addTreatment"].tap()

        let field = app.textFields["search.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the catalogue did not open")
        field.tap()
        field.typeText("nicorette")

        // Skipped, not failed, when the catalogue does not answer — the local
        // Edge Function runs on openFDA's shared per-IP allowance, and a red
        // run that means "somebody else used the quota" teaches people to
        // ignore red runs.
        let facts = app.buttons["search.facts"].firstMatch
        guard facts.waitForExistence(timeout: 20) else {
            throw XCTSkip("openFDA returned nothing for 'nicorette', so L5 could not be reached.")
        }
        facts.tap()

        // By identifier across element types: `children: .combine` folds the
        // panel into a single element whose class XCUITest reports as
        // StaticText, and a query pinned to one type is a test that breaks
        // when the fold changes shape.
        let panel = app.descendants(matching: .any)["facts.panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "the info button opened no label")
        XCTAssertTrue(
            panel.label.contains("Purpose") && panel.label.contains("Stop smoking aid"),
            "the Drug Facts panel did not read as a label"
        )

        app.buttons["facts.plus"].tap()
        app.buttons["facts.log"].tap()

        // L6 first: the accent cover with the day's meter and one way out.
        let done = app.buttons["logged.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "logging showed no confirmation")
        XCTAssertTrue(app.staticTexts["Logged."].exists, "the cover did not say what happened")
        done.tap()

        // Then the pad: the write landed and the search's job is done.
        XCTAssertTrue(
            app.buttons[pouches].waitForExistence(timeout: 10),
            "logging from the label did not come back to the pad"
        )
        // The tally the meter reads counts sources only, so a treatment logged
        // from the catalogue must leave it exactly where it was.
        XCTAssertTrue(
            app.staticTexts["0 of 18 mg today"].waitForExistence(timeout: 5),
            "a treatment logged from the catalogue moved the source tally"
        )
    }

    /// Not an assertion run: walks onboarding, scrolls home to the bottom and
    /// saves screenshots, so the new cards can be looked at with designer
    /// eyes rather than trusted off a green suite.
    func testHomeScrolledScreenshots() throws {
        reachTheTabs()
        let home = app.scrollViews.firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        sleep(2)
        home.swipeUp()
        try save(app.screenshot(), as: "home-middle")
        home.swipeUp()
        try save(app.screenshot(), as: "home-bottom")
    }

    /// Throws rather than shrugging: a screenshot test that cannot write its
    /// screenshots has produced nothing, and passing anyway would report the
    /// artifacts exist when they do not.
    private func save(_ screenshot: XCUIScreenshot, as name: String) throws {
        try screenshot.pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/taper-\(name).png"))
    }
}
