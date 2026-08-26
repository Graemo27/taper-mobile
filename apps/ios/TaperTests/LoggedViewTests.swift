import Foundation
import Testing
@testable import Taper

/// Covers what the logged screen says — the one celebratory surface, kept
/// factual.
struct LoggedViewTests {
    private func view(logged: Double, ceiling: Double) -> LoggedView {
        let entry = StoredCheckIn(id: 1, ledger: .source, label: "Pouches",
                                  form: .pouch, mg: logged, quantity: 1,
                                  loggedOn: "2026-08-26",
                                  createdAt: Date(timeIntervalSince1970: 0))
        return LoggedView(
            tally: TodaysTally(entries: logged > 0 ? [entry] : [], pending: nil,
                               ceilingMg: ceiling),
            onDone: {}
        )
    }

    @Test("under the cap it reports the remainder, and does not demand a return")
    func theSeeYouIsOptional() {
        let under = view(logged: 10.5, ceiling: 12)

        #expect(under.figureText == "10.5 of 12 mg today")
        #expect(under.remainderText == "1.5 mg left")
        #expect(under.sentence == "Still under today's cap. See you at the next craving — or don't.")
        #expect(under.fillFraction == 10.5 / 12)
    }

    @Test("over the cap it says the position in one line, and the bar reports full")
    func notedNotJudged() {
        let over = view(logged: 13.5, ceiling: 12)

        #expect(over.remainderText == "1.5 mg over")
        #expect(over.sentence == "You're 1.5 mg over — noted, not judged. Tomorrow's cap still drops.")
        #expect(over.fillFraction == 1, "a past-tense meter overflowed instead of reporting")
    }

    @Test("the quit week's cap of zero does not divide by it")
    func theFloorIsSafe() {
        #expect(view(logged: 0, ceiling: 0).fillFraction == 0)
        #expect(view(logged: 2, ceiling: 0).fillFraction == 1)
    }
}
