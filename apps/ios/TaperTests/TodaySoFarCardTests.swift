import Foundation
import Testing
@testable import Taper

/// Covers what home's tracking card says about a day, including the two states
/// that are not "here is your total".
@MainActor
struct TodaySoFarCardTests {
    private func card(
        _ status: DayStatus, tally: TodaysTally,
        breakdown: DayBreakdown? = nil, outlasted: Int = 0
    ) -> TodaySoFarCard {
        TodaySoFarCard(status: status, tally: tally, breakdown: breakdown,
                       outlastedCount: outlasted, onCheckIn: {}, onSeeHistory: {})
    }

    private func tally(logged: Double, ceiling: Double = 12) -> TodaysTally {
        TodaysTally(
            entries: [StoredCheckIn(id: 1, ledger: .source, label: "Pouches",
                                    form: .pouch, mg: logged, quantity: 1, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment)],
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

    @Test("the bar says nothing while the figure says nothing")
    func aDashIsNotDrawnOverAFullBar() {
        // `TodayRecord` keeps the last day's entries through a reload and
        // through a failed read, so the tally handed over here can be a real
        // day while the status is not ready. Drawing it would put a filled bar
        // — a red one, past the cap — under an em dash: the figure saying it
        // does not know and the bar answering anyway.
        let reloading = card(.loading, tally: tally(logged: 14))
        let failed = card(.unavailable("Couldn't load today."), tally: tally(logged: 14))

        #expect(reloading.trackTally.loggedMg == 0, "a reload drew the day it had not re-read")
        #expect(failed.trackTally.loggedMg == 0, "a failed read drew the day it could not see")
        #expect(!failed.trackTally.isOver, "a failed read drew an overflow segment")
        // The ceiling stays, so the empty track is still the right width for
        // the day it is about.
        #expect(reloading.trackTally.ceilingMg == 12)

        #expect(card(.ready, tally: tally(logged: 14)).trackTally.loggedMg == 14)
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

        // And said, not only coloured. Red does not reach VoiceOver, so a
        // reader who cannot see the figure would hear the two numbers and be
        // left to compare them.
        #expect(over.spokenTotalText == "Today so far, 14 of 12 milligrams, over today's cap")
        #expect(under.spokenTotalText == "Today so far, 7.5 of 12 milligrams")
    }

    @Test("the breakdown and the outlasted line wait for the day, like the figure")
    func nothingCountsUnderAnEmDash() {
        // The record keeps the last day's entries through a failed read, so
        // both could describe a real day while the figure says it does not
        // know — two answers to one question, the thing this card exists to
        // avoid.
        let pad = Pad(keys: [StoredPadKey(id: 1, form: .pouch, label: "Pouches",
                                          mg: 3, position: 0, ndc: nil)])
        let breakdown = DayBreakdown(pad: pad, entries: [])
        let failed = card(.unavailable("no"), tally: tally(logged: 3),
                          breakdown: breakdown, outlasted: 2)

        #expect(failed.shownBreakdown == nil, "a breakdown was drawn under an em dash")
        #expect(failed.outlastedText == nil, "an outlasted line was drawn under an em dash")
    }

    @Test("the outlasted line says the count, and nothing at zero")
    func theLineReportsRatherThanApologises() {
        let ready = tally(logged: 3)

        #expect(card(.ready, tally: ready, outlasted: 2).outlastedText
                == "Also today: 2 cravings outlasted · +0 mg")
        #expect(card(.ready, tally: ready, outlasted: 1).outlastedText
                == "Also today: 1 craving outlasted · +0 mg")
        #expect(card(.ready, tally: ready, outlasted: 0).outlastedText == nil,
                "the card reported the absence of cravings")
    }
}
