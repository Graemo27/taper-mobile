import Foundation
import Testing
@testable import Taper

/// Covers a day that is over, read back in a line.
@MainActor
struct DayRollupTests {
    private let day = Date(timeIntervalSince1970: 1_780_000_000)

    private func entry(_ id: Int, mg: Double, quantity: Int = 1,
                       ledger: PadKey.Ledger = .source) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: ledger, label: "Pouch", form: .pouch,
                      mg: mg, quantity: quantity,
                      loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment)
    }

    private func rollup(_ entries: [StoredCheckIn], cap: Double?) -> DayRollup {
        DayRollup(day: day, entries: entries, capMg: cap)
    }

    @Test("treatment is counted in the day and not against the cap")
    func aPatchIsNotSpending() {
        // The same rule the cap counts by. The list shows what happened, so a
        // patch is a check-in; the total is what was spent, so it is not in it.
        let day = rollup([
            entry(1, mg: 3),
            entry(2, mg: 14, ledger: .treatment),
        ], cap: 12)

        #expect(day.checkInCount == 2)
        #expect(day.loggedMg == 3, "the treatment was charged to the day")
        #expect(!day.isOver)
    }

    @Test("a day with no plan is not over its cap, however much is on it")
    func anUnmeasuredDayIsNotJudged() {
        // Days before the plan began have no ceiling. Drawing one as zero would
        // paint every check-in on them as over — the app judging days it was
        // not keeping.
        let day = rollup([entry(1, mg: 30)], cap: nil)

        #expect(!day.isOver)
        #expect(day.fraction == 0)
        #expect(day.totalText == "30 mg", "a day with no cap quoted one anyway")
        #expect(day.summarySentence == "No cap was set for this day.")
    }

    @Test("an over-cap day fills its bar rather than running past the end")
    func aFinishedDayHasNoOverflowTail() {
        // Today's meter rescales to show an overflow, because today is a
        // decision in progress. A day that is over is a fact: the bar fills and
        // the colour says the rest.
        let over = rollup([entry(1, mg: 20)], cap: 12)

        #expect(over.isOver)
        #expect(over.fraction == 1, "the bar ran past its own end")
        #expect(over.totalText == "20 of 12 mg")
        #expect(over.summarySentence == "Over cap. Noted, not judged.")
    }

    @Test("a day under its cap says so without saying anything else")
    func anOrdinaryDayIsReportedPlainly() {
        let under = rollup([entry(1, mg: 3), entry(2, mg: 3)], cap: 12)

        #expect(under.fraction == 0.5)
        #expect(under.countText == "2 check-ins")
        #expect(under.summarySentence == "Under cap.")
    }

    @Test("one check-in is not plural")
    func theCountIsWrittenInEnglish() {
        #expect(rollup([entry(1, mg: 3)], cap: 12).countText == "1 check-in")
        #expect(rollup([], cap: 12).countText == "0 check-ins")
    }

    @Test("a cap of zero does not divide by itself")
    func theEndOfATaperDoesNotCrash() {
        // The last week of a plan that reaches zero. A bar dividing by it would
        // be a crash on the day somebody finishes.
        let finished = rollup([entry(1, mg: 3)], cap: 0)

        #expect(finished.fraction == 0)
        #expect(finished.isOver, "3 mg against a cap of zero is over")
    }
}
