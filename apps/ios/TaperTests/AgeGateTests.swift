import Foundation
import Testing
@testable import Taper

/// Covers L0 — the age gate.
///
/// Almost every test here sits on a boundary, because a gate is nothing but its
/// boundaries: the day someone turns eighteen, the day before it, a date that
/// looks like a date and is not, and the difference between an answer that is
/// wrong and one that is not finished.
struct AgeGateTests {
    /// A fixed day, so the suite never has to guess what today is.
    private let today = date(2026, 8, 19)

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func entry(_ month: String, _ day: String, _ year: String) -> BirthdateEntry {
        BirthdateEntry(month: month, day: day, year: year)
    }

    private func verdict(_ month: String, _ day: String, _ year: String) -> AgeGate.Verdict {
        AgeGate.verdict(for: entry(month, day, year), on: today)
    }

    // MARK: - The boundary the gate exists for

    @Test("the eighteenth birthday itself is old enough")
    func theBirthdayCounts() {
        // Turning eighteen today is being eighteen. Off by one here refuses a
        // legal adult on the single day they are most likely to try.
        #expect(verdict("08", "19", "2008") == .adult)
    }

    @Test("the day before the eighteenth birthday is not")
    func theDayBeforeIsNot() {
        #expect(verdict("08", "20", "2008") == .underage)
    }

    @Test("comfortably either side lands where it should")
    func theOrdinaryCases() {
        #expect(verdict("01", "01", "1990") == .adult)
        #expect(verdict("06", "15", "2015") == .underage)
    }

    @Test("a birthday later this year is still under age")
    func laterThisYearIsStillUnder() {
        // The failure a year subtraction makes: 2008 is eighteen years before
        // 2026, so a check that only compares years calls December an adult.
        #expect(verdict("12", "31", "2008") == .underage)
    }

    // MARK: - Dates that are not dates

    @Test("an impossible day is refused rather than rolled forward")
    func impossibleDatesAreRefused() {
        // Building this by hand gives 3 March, which would silently accept the
        // typo and then compute an age from a day that never existed.
        #expect(verdict("02", "31", "1990") == .unreadable)
        #expect(verdict("13", "01", "1990") == .unreadable)
        #expect(verdict("00", "10", "1990") == .unreadable)
        #expect(verdict("04", "31", "1990") == .unreadable)
    }

    @Test("29 February is real in a leap year and not otherwise")
    func leapDayIsJudgedByTheCalendar() {
        #expect(verdict("02", "29", "2000") == .adult)
        #expect(verdict("02", "29", "1999") == .unreadable)
    }

    @Test("someone born on a leap day still comes of age")
    func aLeapDayBirthdayReachesEighteen() {
        // 2008 was a leap year and 2026 is not, so this birthday has no date to
        // fall on. The calendar decides when it counts; what matters is that it
        // does count, rather than leaving one person permanently seventeen.
        let birthday = AgeGate.verdict(for: entry("02", "29", "2008"), on: Self.date(2026, 3, 1))
        #expect(birthday == .adult)
    }

    @Test("a date in the future is not a birthdate")
    func theFutureIsRefused() {
        #expect(verdict("01", "01", "2030") == .unreadable)
        // Tomorrow, not just next decade — the near case is the one a year
        // comparison would let through.
        #expect(AgeGate.verdict(for: entry("08", "20", "2026"), on: today) == .unreadable)
    }

    @Test("today is a readable birthdate, and belongs to a newborn")
    func todayIsNotRefused() {
        #expect(verdict("08", "19", "2026") == .underage)
    }

    @Test("a mistyped year from centuries ago is caught rather than admitted")
    func implausiblyOldIsRefused() {
        // True and useless: 1823 is over eighteen. It is also a typo, and
        // letting it pass means the one input this screen checks went
        // unchecked.
        #expect(verdict("01", "01", "1823") == .unreadable)
        #expect(verdict("01", "01", "1910") == .adult)
    }

    // MARK: - Still typing is not an error

    @Test("a half-filled entry reads as unfinished, never as wrong")
    func partialEntriesAreIncomplete() {
        // Shown as an error, this puts a refusal under someone who is mid-way
        // through their birth year and has done nothing wrong.
        #expect(verdict("", "", "") == .incomplete)
        #expect(verdict("08", "", "") == .incomplete)
        #expect(verdict("08", "19", "") == .incomplete)
        #expect(verdict("08", "19", "20") == .incomplete)
        #expect(verdict("08", "19", "200") == .incomplete)
    }

    @Test("a four-digit year is what makes an entry complete")
    func completenessNeedsAFullYear() {
        #expect(entry("08", "19", "2008").isComplete)
        #expect(entry("08", "19", "208").isComplete == false)
    }

    @Test("letters in a box are unreadable, not merely unfinished")
    func nonNumericEntriesAreUnreadable() {
        #expect(verdict("ab", "19", "2008") == .unreadable)
    }

    @Test("a leading zero reads the same as the bare digit")
    func leadingZerosAreFine() {
        #expect(verdict("08", "09", "2000") == .adult)
        #expect(verdict("8", "9", "2000") == .adult)
    }

    // MARK: - What the device remembers

    @Test("the record survives, and holds the answer rather than the birthdate")
    func theRecordKeepsOnlyTheVerdict() {
        let defaults = UserDefaults(suiteName: "taper.tests.agegate")!
        defaults.removePersistentDomain(forName: "taper.tests.agegate")
        let store = DeviceAdultVerification(defaults: defaults)

        #expect(store.isVerifiedAdult == false)
        store.recordAdult()
        #expect(store.isVerifiedAdult)

        // A second store over the same defaults is what a relaunch looks like.
        #expect(DeviceAdultVerification(defaults: defaults).isVerifiedAdult)

        // Nothing resembling a date of birth was kept. The gate asks once, and
        // data nobody needs is safest not held.
        let kept = defaults.dictionaryRepresentation().values.map { String(describing: $0) }
        #expect(kept.contains { $0.contains("2008") } == false)

        defaults.removePersistentDomain(forName: "taper.tests.agegate")
    }
}
