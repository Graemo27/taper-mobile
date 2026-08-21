import Foundation
import Testing
@testable import Taper

private func logged(_ mg: Double) -> [StoredCheckIn] {
    [StoredCheckIn(id: 1, ledger: .source, label: "Pouches", form: .pouch, mg: mg, quantity: 1)]
}

private func tap(_ mg: Double) -> PendingEntry {
    PendingEntry(key: StoredPadKey(id: 1, form: .pouch, label: "Pouch", mg: mg, position: 0, ndc: nil))
}

/// Covers the one piece of the meter that is arithmetic rather than layout.
@MainActor
struct CapMeterTests {
    private let track: CGFloat = 362

    @Test("three segments and their gaps fit the track exactly")
    func theBarDoesNotRunPastItsOwnEnd() {
        // The fractions sum to 1 once somebody is over the cap. Sizing each
        // against the full width and *then* spacing them apart puts the last
        // one past the end, where the capsule clip eats it — and the last one
        // is the overflow, which is the segment nobody can afford to lose.
        let tally = TodaysTally(entries: logged(10), pending: tap(4), ceilingMg: 12)
        #expect(tally.loggedFraction + tally.pendingFraction + tally.overflowFraction == 1)

        let widths = CapMeter.segmentWidths(in: track, for: tally)
        let drawn = widths.logged + widths.pending + widths.overflow
        let gaps = 2 * CapMeter.gap

        #expect(drawn + gaps == track, "the segments and their gaps did not fit the track")
    }

    @Test("two segments leave room for one gap, not two")
    func onlyTheGapsThatExistAreSubtracted() {
        // Under the cap there is no overflow, so a fixed allowance of two gaps
        // would leave the bar two points short of where it should reach.
        let tally = TodaysTally(entries: logged(7.5), pending: tap(3), ceilingMg: 12)
        #expect(tally.overflowFraction == 0)

        let widths = CapMeter.segmentWidths(in: track, for: tally)

        #expect(widths.overflow == 0)
        // One gap taken out of the track, and the two segments share what is
        // left in proportion. A fixed allowance of two gaps would leave the bar
        // two points short of where it should reach.
        #expect(widths.logged + widths.pending == (track - CapMeter.gap) * 0.875)
    }

    @Test("one segment takes the whole track")
    func aRestingDayHasNoGapsToAllowFor() {
        let tally = TodaysTally(entries: logged(6), pending: nil, ceilingMg: 12)

        let widths = CapMeter.segmentWidths(in: track, for: tally)

        #expect(widths.logged == track * 0.5, "a lone segment was shortened for a gap beside nothing")
        #expect(widths.pending == 0)
        #expect(widths.overflow == 0)
    }

    @Test("an empty day draws nothing rather than something of zero width")
    func nothingLoggedIsNothingDrawn() {
        let widths = CapMeter.segmentWidths(in: track, for: TodaysTally(entries: [], pending: nil, ceilingMg: 12))

        #expect(widths.logged == 0)
        #expect(widths.pending == 0)
        #expect(widths.overflow == 0)
    }

    @Test("a track with no width does not produce a negative one")
    func theFirstLayoutPassIsSurvivable() {
        // `GeometryReader` reports zero before it has been measured, and a
        // negative frame width is a runtime crash rather than a bad drawing.
        let tally = TodaysTally(entries: logged(10), pending: tap(4), ceilingMg: 12)

        let widths = CapMeter.segmentWidths(in: 0, for: tally)

        #expect(widths.logged == 0)
        #expect(widths.pending == 0)
        #expect(widths.overflow == 0)
    }
}
