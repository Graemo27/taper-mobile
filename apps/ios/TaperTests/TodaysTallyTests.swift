import Foundation
import Testing
@testable import Taper

private func entry(_ ledger: PadKey.Ledger, mg: Double, quantity: Int = 1) -> StoredCheckIn {
    StoredCheckIn(
        id: 1,
        ledger: ledger,
        label: ledger == .source ? "Pouch" : "Lozenge",
        form: ledger == .source ? .pouch : .lozenge,
        mg: mg,
        quantity: quantity
    )
}

private func padKey(_ ledger: PadKey.Ledger, mg: Double) -> StoredPadKey {
    StoredPadKey(
        id: 1,
        form: ledger == .source ? .pouch : .lozenge,
        label: ledger == .source ? "Pouch" : "Lozenge",
        mg: mg,
        position: 0,
        ndc: nil
    )
}

/// Covers the day's arithmetic: what counts, what does not, and what is said
/// about going over.
struct TodaysTallyTests {
    @Test("only what you're quitting counts toward the ceiling")
    func treatmentIsLoggedButNotCounted() {
        // The rule the pad states on its own face: one section is labelled
        // "counts toward the ceiling" and the other is not. Counting a patch
        // against somebody would make using the treatment look like failing at
        // the taper, which is the opposite of what it is.
        let tally = TodaysTally(
            entries: [entry(.source, mg: 3), entry(.treatment, mg: 21)],
            pending: nil,
            ceilingMg: 12
        )

        #expect(tally.loggedMg == 3, "a treatment was counted against the cap")
        #expect(!tally.isOver, "21 mg of patch put somebody over a 12 mg ceiling")
    }

    @Test("a pending treatment adds nothing either")
    func aPendingTreatmentIsNotCounted() {
        let tally = TodaysTally(
            entries: [],
            pending: PendingEntry(key: padKey(.treatment, mg: 21)),
            ceilingMg: 12
        )

        #expect(tally.pendingMg == 0)
        #expect(!tally.isOver)
    }

    @Test("quantity multiplies the strength")
    func severalOfAThingCountSeveralTimes() {
        let tally = TodaysTally(
            entries: [entry(.source, mg: 3, quantity: 4)],
            pending: PendingEntry(key: padKey(.source, mg: 3), quantity: 2),
            ceilingMg: 24
        )

        #expect(tally.loggedMg == 12)
        #expect(tally.pendingMg == 6)
        #expect(tally.projectedMg == 18)
    }

    @Test("a quantity the column would reject is clamped before it can be sent")
    func quantityStaysInsideTheConstraint() {
        // `check (quantity between 1 and 20)`. A number outside it is a
        // rejected insert *after* the tap — the failure arrives once the user
        // thinks they have logged something.
        #expect(PendingEntry(key: padKey(.source, mg: 3), quantity: 0).quantity == 1)
        #expect(PendingEntry(key: padKey(.source, mg: 3), quantity: 99).quantity == 20)
        #expect(PendingEntry(key: padKey(.source, mg: 3), quantity: 7).quantity == 7)
    }

    @Test("going over is reported, never refused")
    func theAppIsAWitnessNotAReferee() {
        // "Never shame. The app is a witness, not a referee." Nothing here
        // clamps, blocks or discounts — a tracker that argues gets closed, and
        // a number that has been quietly capped makes the whole log worthless.
        let tally = TodaysTally(
            entries: [entry(.source, mg: 12)],
            pending: PendingEntry(key: padKey(.source, mg: 1.5)),
            ceilingMg: 12
        )

        #expect(tally.projectedMg == 13.5, "the projected total was clamped to the cap")
        #expect(tally.isOver)
        #expect(tally.overByMg == 1.5)
    }

    @Test("under the cap, the bar is the cap")
    func theMeterMeasuresAgainstTheCeiling() {
        // 7.5 logged and 3 pending against 12: the board's own numbers, where
        // the two segments fill 62.5% and 25% of the track.
        let tally = TodaysTally(
            entries: [entry(.source, mg: 7.5)],
            pending: PendingEntry(key: padKey(.source, mg: 3)),
            ceilingMg: 12
        )

        #expect(tally.loggedFraction == 0.625)
        #expect(tally.pendingFraction == 0.25)
        #expect(tally.overflowFraction == 0)
    }

    @Test("over the cap, the bar rescales so the overflow is visible")
    func theOverflowIsDrawnHonestly() {
        // A bar pinned at 100% would hide the one number that matters. The
        // board draws 13.5 against 12 as a green run to the cap and a red tail
        // past it — so the whole bar becomes the projected total.
        let tally = TodaysTally(
            entries: [entry(.source, mg: 13.5)],
            pending: nil,
            ceilingMg: 12
        )

        #expect(tally.overflowFraction == 1.5 / 13.5)
        #expect(tally.loggedFraction == 1, "the logged run should fill the whole rescaled bar")
        // And the cap's share of it is what the green run stops at.
        #expect(tally.loggedFraction - tally.overflowFraction == 12 / 13.5)
    }

    @Test("a ceiling of zero does not divide by it")
    func theQuitWeekDoesNotCrash() {
        // The last week of a dated plan has a cap of exactly zero — the schema
        // was built for it, after `current_cap_mg > 0` nearly shipped.
        let empty = TodaysTally(entries: [], pending: nil, ceilingMg: 0)
        #expect(empty.loggedFraction == 0)
        #expect(!empty.isOver)

        let used = TodaysTally(entries: [entry(.source, mg: 3)], pending: nil, ceilingMg: 0)
        #expect(used.isOver)
        #expect(used.overByMg == 3)
        #expect(used.overflowFraction == 1)
    }

    @Test("the question is asked before the tap and not after")
    func goingOverIsAskedOnceAndThenLetGo() {
        // Asked while the decision is still theirs to make...
        let about = TodaysTally(
            entries: [entry(.source, mg: 12)],
            pending: PendingEntry(key: padKey(.source, mg: 1.5)),
            ceilingMg: 12
        )
        #expect(about.questionBeforeLogging?.contains("Log it anyway?") == true)

        // ...and never again once it has been made. Asking a second time would
        // be the app relitigating something it has already been told.
        let after = TodaysTally(
            entries: [entry(.source, mg: 13.5)],
            pending: PendingEntry(key: padKey(.source, mg: 1.5)),
            ceilingMg: 12
        )
        #expect(after.questionBeforeLogging == nil)
    }

    @Test("what is said after going over promises the plan does not move")
    func tomorrowsCapStillDrops() {
        // The second half is the load-bearing half. A taper that punished a bad
        // day by extending itself would make the schedule a performance review,
        // and failing a schedule is associated with worse outcomes than never
        // being given one.
        let tally = TodaysTally(entries: [entry(.source, mg: 13.5)], pending: nil, ceilingMg: 12)

        let note = tally.noteAfterGoingOver
        #expect(note?.contains("1.5 mg over") == true)
        #expect(note?.contains("noted, not judged") == true)
        #expect(note?.contains("Tomorrow's cap still drops") == true)
    }

    @Test("nothing is said about going over to somebody who has not")
    func theUnderCapDayIsQuiet() {
        let tally = TodaysTally(entries: [entry(.source, mg: 3)], pending: nil, ceilingMg: 12)

        #expect(tally.questionBeforeLogging == nil)
        #expect(tally.noteAfterGoingOver == nil)
        #expect(tally.overByMg == 0, "'0 mg over' is not a thing to say to somebody who is under")
    }

    @Test("the readout names the projection while one is pending, and the day when none is")
    func theLineUnderTheMeterFollowsTheState() {
        let pending = TodaysTally(
            entries: [entry(.source, mg: 7.5)],
            pending: PendingEntry(key: padKey(.source, mg: 3)),
            ceilingMg: 12
        )
        #expect(pending.readout == "puts you at 10.5 — today's ceiling is 12 mg")

        let idle = TodaysTally(entries: [entry(.source, mg: 7.5)], pending: nil, ceilingMg: 12)
        #expect(idle.readout == "7.5 of 12 mg today")

        let over = TodaysTally(entries: [entry(.source, mg: 13.5)], pending: nil, ceilingMg: 12)
        #expect(over.readout == "1.5 mg over today's cap")
    }

    @Test("a pending entry is read back the way the board reads it")
    func theRecapNamesTheKeyAndTheCount() {
        #expect(PendingEntry(key: padKey(.source, mg: 3)).recap == "Pouch × 1")
        #expect(PendingEntry(key: padKey(.source, mg: 3), quantity: 3).recap == "Pouch × 3")
    }
}
