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
                      form: form, mg: mg, quantity: quantity, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment)
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

    @Test("only the actual day before today is called Yesterday")
    func theHeadingIsAFactAboutTheDateNotThePosition() {
        // The head of the list is called Yesterday only if it *is* yesterday.
        // A window that arrived stale, or a list built in another order, would
        // otherwise rename whatever happened to be first — and a week-old day
        // labelled "Yesterday" with its own cap beside it is this feature's
        // signature bug.
        let cal = Calendar.current
        let today = Date()
        func day(_ o: Int) -> Date {
            cal.date(byAdding: .day, value: o, to: cal.startOfDay(for: today))!
        }
        func rollup(_ o: Int) -> DayRollup {
            DayRollup(day: day(o), entries: [], capMg: 12)
        }

        let correct = TodayListView(status: .ready, entries: [], summary: "", onBack: {},
                                    onSelect: { _ in }, pastDays: [rollup(-1), rollup(-2)],
                                    today: today)
        #expect(correct.heading(for: rollup(-1)) == "Yesterday")
        #expect(correct.heading(for: rollup(-2)) == rollup(-2).weekdayText)

        // The same list with its newest day two days back — what a stale window
        // looks like. Nothing in it is yesterday, so nothing is called it.
        let stale = TodayListView(status: .ready, entries: [], summary: "", onBack: {},
                                  onSelect: { _ in }, pastDays: [rollup(-2), rollup(-3)],
                                  today: today)
        #expect(
            stale.heading(for: rollup(-2)) == rollup(-2).weekdayText,
            "the head of a stale window was renamed Yesterday"
        )
        #expect(stale.countLine(for: rollup(-2)).contains(rollup(-2).dateText),
                "and it lost the date that would have given it away")
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

    @Test("a row says which form it was and when")
    func theSubtitleNamesTheFormAndTheTime() {
        // The label is what somebody recognises — a product name, often — and
        // the form is the category it files under. "Nicorette ice mint" tells
        // you nothing about whether it counts against the cap; "Gum" does.
        let gum = CheckInListRow(entry: StoredCheckIn(
            id: 1, ledger: .treatment, label: "Nicorette ice mint",
            form: .gum, mg: 2, quantity: 1, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment
        ))

        #expect(gum.entry.detailText.hasPrefix("Gum · "))
        #expect(gum.entry.timeText == gum.entry.timeText.lowercased(), "the clock shouted")
        #expect(!gum.entry.timeText.isEmpty)

        // A time, not a date. Every row on this screen is today's, so the date
        // would be the same noise repeated down the column — and the year is
        // the part that gives away a formatter reaching for one.
        let year = String(Calendar.current.component(.year, from: .testMoment))
        #expect(!gum.entry.timeText.contains(year), "the row printed the date as well as the time")
    }

    @Test("what a row says out loud carries the form the row shows")
    func theListenedRowIsNotThePoorerOne() {
        // The form is the one word that says whether a row counts against the
        // cap. A product name does not: somebody listening to "Nicorette ice
        // mint, 2 milligrams" has been told everything except the part that
        // decides what it means.
        let gum = CheckInListRow(entry: StoredCheckIn(
            id: 1, ledger: .treatment, label: "Nicorette ice mint",
            form: .gum, mg: 2, quantity: 1, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment
        ))

        #expect(gum.spokenText.contains("Gum"), "the spoken row dropped the form")
        #expect(gum.spokenText.hasPrefix("Nicorette ice mint, Gum, 2 milligrams, "))

        // And a label that is the form in different clothes is still the form.
        // Source labels will be typed by hand once adding a key is built, and
        // "pouch" is what somebody types; hearing "pouch, Pouch" back would
        // read as a bug in the app rather than a difference in case.
        let typed = CheckInListRow(entry: StoredCheckIn(
            id: 2, ledger: .source, label: "pouch",
            form: .pouch, mg: 3, quantity: 1, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment
        ))

        #expect(typed.spokenText.hasPrefix("pouch, 3 milligrams, "), "the form was said twice")
    }

    @Test("a source with no form of its own says so rather than borrowing one")
    func otherIsNamedHonestly() {
        // `.other` is whatever somebody typed for a source with no case of its
        // own. Calling it "Pouch" because that is the nearest shape would put a
        // word in their mouth about what they are quitting.
        #expect(PadForm.other.label == "Something else")
        #expect(PadForm.cigarette.label == "Cigarette")
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

        // The time is deliberately not pinned: it is rendered in the runner's
        // own zone, so a fixed instant reads as a different clock time
        // depending on where the machine is.
        //
        // "Pouch" filed under `.pouch` — the label already is the form, so it
        // is not said twice. That is the board's own first row.
        #expect(row.spokenText.hasPrefix("Pouch × 2, 6 milligrams, "))
        #expect(row.spokenText.hasSuffix(row.entry.timeText))
    }

    @Test("an empty day and an unreadable one are different screens")
    func nothingLoggedIsNotAFailedRead() {
        // The distinction the whole app is built on. "Nothing logged today
        // yet" over a day that could not be read is what invites a second
        // dose against a day the app cannot see.
        let empty = TodayListView(status: .ready, entries: [], summary: "0 check-ins · 0 of 12 mg",
                                  onBack: {}, onSelect: { _ in })
        let failed = TodayListView(status: .unavailable("Couldn't load today."), entries: [],
                                   summary: "0 check-ins · 0 of 12 mg", onBack: {}, onSelect: { _ in })

        #expect(empty.isEmptyDay)
        #expect(!failed.isEmptyDay, "a failed read was drawn as a day with nothing on it")
        #expect(failed.failureText == "Couldn't load today.")
        #expect(empty.failureText == nil)
    }

    @Test("the header's numbers are dropped when the day is not known")
    func aStaleTotalDoesNotOutliveItsDay() {
        // `TodayRecord` keeps the last day's entries through a reload and
        // through a failed read, so this sentence can describe a real day
        // while the body below it is a spinner or an apology — the header
        // answering confidently while the screen says it does not know.
        //
        // The same defect the card's bar had, and the same fix.
        let real = "3 check-ins · 7.5 of 12 mg"

        #expect(TodayListView(status: .ready, entries: [], summary: real, onBack: {}, onSelect: { _ in })
            .summaryText == real)
        #expect(TodayListView(status: .loading, entries: [], summary: real, onBack: {}, onSelect: { _ in })
            .summaryText == nil, "a reload kept the last day's count in the header")
        #expect(TodayListView(status: .unavailable("Couldn't load today."), entries: [],
                              summary: real, onBack: {}, onSelect: { _ in })
            .summaryText == nil, "a failed read kept the last day's total in the header")
    }

    @Test("a day still loading is neither of those")
    func loadingIsItsOwnState() {
        let loading = TodayListView(status: .loading, entries: [], summary: "", onBack: {}, onSelect: { _ in })

        #expect(!loading.isEmptyDay, "a day still loading was drawn as an empty one")
        #expect(loading.failureText == nil)
    }
}

extension Date {
    /// A fixed moment for tests that construct a stored check-in.
    ///
    /// Most of them do not care when it happened; the ones that print a time
    /// need it not to move. 2026-08-22, 12:40 — the board's own example row.
    static let testMoment = Date(timeIntervalSince1970: 1_787_402_400)
}
