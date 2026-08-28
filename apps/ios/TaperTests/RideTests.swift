import Foundation
import Testing
@testable import Taper

/// Covers L8a's two minutes: what the ring draws, what the sequence asks for,
/// and what happens to a timer nobody was watching.
struct RideTests {
    private let start = Date(timeIntervalSince1970: 1_780_000_000)

    private func ride(_ seconds: TimeInterval) -> Ride {
        Ride(startedAt: start, now: start.addingTimeInterval(seconds))
    }

    @Test("the ring is drawn from the clock, not from how often anybody looked")
    func aLockedPhoneStillRidesItOut() {
        // The reason this is derived rather than accumulated. Somebody who
        // locks their phone for ninety seconds of a two-minute craving has
        // ridden out ninety seconds of it, and a tick counter would have
        // stopped with the screen — coming back to say they had barely begun.
        #expect(ride(90).fraction == 0.75)
        #expect(ride(90).remainingText == "0:30")

        // And one that outlasts the whole span comes back finished, not stuck
        // at whatever it reached before the app went away.
        #expect(ride(600).isDone)
        #expect(ride(600).fraction == 1)
        #expect(ride(600).remainingText == "0:00")
    }

    @Test("the sequence is three equal thirds, and the last one keeps the end")
    func eachStepGetsFortySeconds() {
        #expect(ride(0).step == .notice)
        #expect(ride(39).step == .notice)
        #expect(ride(40).step == .name)
        #expect(ride(79).step == .name)
        #expect(ride(80).step == .ride)
        #expect(ride(120).step == .ride, "the final instant fell off the end of the sequence")
    }

    @Test("every step asks about the body, because that is the half that mediates")
    func nothingAsksThemToThinkAboutIt() {
        // The largest mediation study on file: acceptance of physical
        // sensations and emotions carried the whole effect, thoughts did not
        // mediate at all. A step asking somebody to reason about their craving
        // is the one thing here with evidence against it.
        let words = Ride.Step.allCases.map(\.instruction).joined(separator: " ").lowercased()
        #expect(words.contains("where is it"))
        #expect(words.contains("size and a shape"))
        #expect(!words.contains("think"), "a step asked them to think about the craving")
        #expect(!words.contains("remember"), "a step asked them to reason rather than notice")
    }

    @Test("a clock that goes backwards does not draw a ring past full")
    func timeCannotRunNegative() {
        // A manual change or an NTP correction, and the ring would otherwise
        // sweep the wrong way with a countdown above two minutes.
        let backwards = Ride(startedAt: start, now: start.addingTimeInterval(-30))
        #expect(backwards.elapsed == 0)
        #expect(backwards.fraction == 0)
        #expect(backwards.remainingText == "2:00")
        #expect(backwards.step == .notice)
    }

    @Test("the countdown rounds up, so it says two minutes when it starts")
    func aTimerThatOpensAtOneFiftyNineIsAlreadyBehind() {
        #expect(ride(0).remainingText == "2:00")
        #expect(ride(0.4).remainingText == "2:00")
        #expect(ride(1).remainingText == "1:59")
        #expect(ride(119.5).remainingText == "0:01")
        #expect(ride(120).remainingText == "0:00")
    }
}
