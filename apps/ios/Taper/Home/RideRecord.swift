import Foundation
import Observation

/// L8a's state: when the two minutes started, and what time it is now.
///
/// Holds only those two things, because `Ride` derives everything else from
/// them. The ticker exists to redraw, not to count — if it misses a beat, or
/// twenty, the next one still reports the truth. That is what makes a timer
/// survive a locked screen.
@Observable
@MainActor
final class RideRecord {
    private(set) var startedAt: Date?
    private(set) var now: Date

    private let clock: () -> Date

    init(clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        now = clock()
    }

    /// The two minutes as they stand, or nil before anybody started.
    var ride: Ride? {
        startedAt.map { Ride(startedAt: $0, now: now) }
    }

    func begin() {
        let instant = clock()
        startedAt = instant
        now = instant
    }

    /// The clock, never allowed to run backwards.
    ///
    /// Clamping each sample against `startedAt` keeps a single reading sane,
    /// but not a sequence of them: ninety seconds in, an NTP correction or a
    /// manual change lands the next sample at thirty, and the ring rewinds
    /// under somebody who has been sitting still. Worse at the end — a ride
    /// that had finished stops being finished, and the button it earned
    /// disappears.
    ///
    /// So the session keeps the furthest point it has reached. Time only ever
    /// went forward for the person holding the phone.
    private func advance() {
        now = max(now, clock())
    }

    /// Redraws, and reports whether there is still anything to redraw for.
    ///
    /// Returning false is what ends the loop: a `while true` that outlives its
    /// own reason is the shape `a-wait-with-no-bound` is about, and a timer is
    /// the easiest place in an app to write one.
    @discardableResult
    func tick() -> Bool {
        advance()
        return ride?.isDone == false
    }
}

/// Presented as a cover, so it needs an identity. Reference identity is the
/// right one: a ride is one sitting, and opening the card again starts another.
extension RideRecord: Identifiable {}
