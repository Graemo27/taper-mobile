import Foundation
import Testing
@testable import Taper

/// Covers what home's tracking card says about a day, including the two states
/// that are not "here is your total".
@MainActor
struct TodaySoFarCardTests {
    private func card(_ status: DayStatus, tally: TodaysTally) -> TodaySoFarCard {
        TodaySoFarCard(status: status, tally: tally, onCheckIn: {})
    }

    private func tally(logged: Double, ceiling: Double = 12) -> TodaysTally {
        TodaysTally(
            entries: [StoredCheckIn(id: 1, ledger: .source, label: "Pouches",
                                    form: .pouch, mg: logged, quantity: 1)],
            pending: nil,
            ceilingMg: ceiling
        )
    }

    @Test("a day that has not loaded shows a dash, not a zero")
    func anUnknownDayIsNotAnEmptyDay() {
        // The whole reason the card takes a status. A zero here would tell
        // somebody they had used nothing today, on the strength of a request
        // that has not come back — and the reading that invites is a second
        // dose logged against a day the app could not see.
        let card = card(.loading, tally: tally(logged: 7.5))

        #expect(card.figureText == "—", "a day still loading reported a total")
        #expect(card.spokenTotalText.contains("not loaded"))
    }

    @Test("a day that cannot be read says so rather than showing a dash alone")
    func aFailedReadIsExplained() {
        let card = card(.unavailable("Couldn't load today."), tally: tally(logged: 7.5))

        #expect(card.figureText == "—")
        #expect(card.failureText == "Couldn't load today.", "the reason was swallowed")
    }

    @Test("a day that loaded reports what is on it")
    func aReadyDayReportsItsTotal() {
        let card = card(.ready, tally: tally(logged: 7.5))

        #expect(card.figureText == "7.5")
        #expect(card.failureText == nil, "a day that read fine showed a failure")
        #expect(card.spokenTotalText == "Today so far, 7.5 of 12 milligrams")
    }

    @Test("going over is said in the figure, not only in the bar")
    func goingOverColoursTheFigure() {
        // The bar already shows it. The figure has to as well, because the
        // number is what somebody reads at a glance and a black 14 next to a
        // red bar is two answers to one question.
        let over = card(.ready, tally: tally(logged: 14))
        let under = card(.ready, tally: tally(logged: 7.5))

        #expect(over.isOverToday, "the figure did not mark a day over the cap")
        #expect(!under.isOverToday)

        // And only a day that read cleanly can be over one. A reload leaves the
        // last day's entries in hand while the status goes back to loading, so
        // without the guard the dash above would be drawn in red — a breach
        // reported out of a request that has not come back.
        #expect(!card(.loading, tally: tally(logged: 14)).isOverToday, "a dash was marked over")
    }
}
