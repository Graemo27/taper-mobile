import Foundation
import Testing
@testable import Taper

/// Covers L8a's state: what the ticker is for, and what it is not for.
@MainActor
struct RideRecordTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private final class Clock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    @Test("nothing is riding until somebody starts it")
    func aRecordIsNotATimer() {
        #expect(RideRecord(clock: { self.start }).ride == nil)
    }

    @Test("the ticker redraws; the clock is what counts")
    func missedBeatsCostNothing() {
        // The whole reason this holds an instant rather than a tally. One tick
        // after ninety seconds of nothing reports ninety seconds, because it
        // reads the clock rather than adding to a number.
        let clock = Clock(start)
        let record = RideRecord(clock: { clock.now })
        record.begin()

        #expect(record.ride?.fraction == 0)
        clock.now = start.addingTimeInterval(90)
        #expect(record.tick(), "the ride ended early")
        #expect(record.ride?.fraction == 0.75)
    }

    @Test("the loop ends when the ride does")
    func aTickerThatOutlivesItsReasonIsAHang() {
        // `tick()` returning false is what stops the view's loop. Without a
        // bound it spins for as long as the screen is up, which is the shape
        // filed as `a-wait-with-no-bound` — easiest to write in a timer.
        let clock = Clock(start)
        let record = RideRecord(clock: { clock.now })
        record.begin()

        #expect(record.tick())
        clock.now = start.addingTimeInterval(Ride.span)
        #expect(record.tick() == false, "the ticker kept going past the end")
        #expect(record.ride?.isDone == true)
    }

    @Test("a clock correction does not rewind a ride somebody has sat through")
    func timeOnlyWentForwardForThePersonHoldingThePhone() {
        // Clamping each sample keeps one reading sane, not a sequence of them.
        // Ninety seconds in, an NTP correction lands the next sample at
        // thirty and the ring rewinds under somebody sitting still.
        let clock = Clock(start)
        let record = RideRecord(clock: { clock.now })
        record.begin()

        clock.now = start.addingTimeInterval(90)
        record.tick()
        #expect(record.ride?.elapsed == 90)

        clock.now = start.addingTimeInterval(30)
        record.tick()
        #expect(record.ride?.elapsed == 90, "the ride rewound under a backwards clock")
    }

    @Test("a finished ride stays finished")
    func theButtonItEarnedDoesNotDisappear() {
        // The sharper end of the same thing: a completed ride sampled after
        // the clock moves back stops being done, and the count it earned
        // vanishes from the screen.
        let clock = Clock(start)
        let record = RideRecord(clock: { clock.now })
        record.begin()

        clock.now = start.addingTimeInterval(Ride.span)
        #expect(record.tick() == false)
        #expect(record.ride?.isDone == true)

        clock.now = start.addingTimeInterval(10)
        record.tick()
        #expect(record.ride?.isDone == true, "a finished ride came undone")
    }

    @Test("beginning reads one instant, not two")
    func schedulingAndDrawingShareABaseline() {
        // The midnight lesson: scheduling from time and initialising from time
        // have to read the same instant. Two reads a hair apart would open the
        // ring at a fraction already past zero.
        var reads = 0
        let record = RideRecord(clock: {
            reads += 1
            return self.start.addingTimeInterval(Double(reads))
        })
        record.begin()

        #expect(record.ride?.elapsed == 0, "the ring opened already part-drawn")
    }
}
