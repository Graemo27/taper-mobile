import Foundation
import Testing
@testable import Taper

/// Covers what a row of the day's list says, and what the screen says when the
/// day is empty, loading or unreadable.
@MainActor
struct TodayListTests {
    private func entry(_ id: Int, mg: Double, quantity: Int = 1,
                       label: String = "Pouch", form: PadForm = .pouch) -> StoredCheckIn {
        StoredCheckIn(id: id, ledger: .source, label: label,
                      form: form, mg: mg, quantity: quantity)
    }

    @Test("a row shows what the day was charged, not the strength of one")
    func theFigureIsTheTotalNotTheUnit() {
        // Two 3 mg pouches cost the day 6 mg. Printing "3 mg" on a row worth 6
        // would make the column stop adding up to the total in the header
        // above it — and the header is the number the cap is measured on.
        let row = CheckInListRow(entry: entry(1, mg: 3, quantity: 2))

        #expect(row.figureText == "6 mg", "the row printed the unit strength instead of the total")
        #expect(row.labelText == "Pouch × 2", "a repeated tap did not say how many")
    }

    @Test("a multiple prints as a dose, not as a Double")
    func aRowDoesNotLeakItsBinary() {
        // The row that started #110: 1.2 mg three times drew as
        // "3.5999999999999996 mg" on a screen somebody reads to check what
        // they have had. Fixed in the formatter, pinned here as well because
        // this row is where it was seen and where it would be seen again.
        let row = CheckInListRow(entry: entry(1, mg: 1.2, quantity: 3,
                                              label: "Cigarette", form: .cigarette))

        #expect(row.figureText == "3.6 mg")
    }

    @Test("a single tap is not counted at you")
    func oneIsNotWrittenOut() {
        // "Pouch × 1" is noise on the common case.
        let row = CheckInListRow(entry: entry(1, mg: 3))

        #expect(row.labelText == "Pouch")
        #expect(row.figureText == "3 mg")
    }

    @Test("a row says its quantity out loud as well as its total")
    func theRowIsSpokenWhole() {
        let row = CheckInListRow(entry: entry(1, mg: 3, quantity: 2))

        #expect(row.spokenText == "Pouch × 2, 6 milligrams")
    }

    @Test("an empty day and an unreadable one are different screens")
    func nothingLoggedIsNotAFailedRead() {
        // The distinction the whole app is built on. "Nothing logged today
        // yet" over a day that could not be read is what invites a second
        // dose against a day the app cannot see.
        let empty = TodayListView(status: .ready, entries: [], summary: "0 check-ins · 0 of 12 mg",
                                  onBack: {})
        let failed = TodayListView(status: .unavailable("Couldn't load today."), entries: [],
                                   summary: "0 check-ins · 0 of 12 mg", onBack: {})

        #expect(empty.isEmptyDay)
        #expect(!failed.isEmptyDay, "a failed read was drawn as a day with nothing on it")
        #expect(failed.failureText == "Couldn't load today.")
        #expect(empty.failureText == nil)
    }

    @Test("a day still loading is neither of those")
    func loadingIsItsOwnState() {
        let loading = TodayListView(status: .loading, entries: [], summary: "", onBack: {})

        #expect(!loading.isEmptyDay, "a day still loading was drawn as an empty one")
        #expect(loading.failureText == nil)
    }
}
