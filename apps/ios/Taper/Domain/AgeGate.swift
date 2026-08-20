import Foundation

/// Three text fields, before they are a date.
///
/// A separate type from the date it produces, because most of what a user types
/// into three boxes is not a date yet — and the app has to tell "still typing"
/// apart from "typed something impossible". Collapsing both into a nil `Date`
/// would put an error under someone halfway through their birth year.
struct BirthdateEntry: Equatable, Sendable {
    /// Month first, matching the board. Written as strings rather than numbers
    /// because a field holding "0" while someone types "09" is a real state,
    /// and an `Int` cannot hold the difference between that and "typed nothing".
    var month: String = ""
    var day: String = ""
    var year: String = ""

    /// True once every box has enough digits to be worth reading. Not the same
    /// as valid — "13/45/2020" is complete and impossible.
    var isComplete: Bool {
        !month.isEmpty && !day.isEmpty && year.count == 4
    }

    /// The date the three fields name, or nil if they do not name one.
    ///
    /// Uses `DateComponents.isValidDate` rather than arithmetic. Building a
    /// date from 31 February by hand rolls it forward into March, which would
    /// silently accept a typo and then compute an age from a day that does not
    /// exist; asking the calendar refuses it instead.
    func date(calendar: Calendar = .current) -> Date? {
        guard isComplete,
              let month = Int(month), let day = Int(day), let year = Int(year)
        else { return nil }

        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        guard components.isValidDate else { return nil }
        return calendar.date(from: components)
    }
}

/// The one question asked before the app opens: is this an adult?
///
/// The app tracks a drug. It sells nothing and ships nothing, so this is an
/// honesty gate rather than an enforcement one — but the question still has to
/// be asked, and the answer still has to be computed rather than eyeballed.
enum AgeGate {
    static let minimumAge = 18

    /// The oldest birthdate treated as real.
    ///
    /// A gate with no floor accepts 1823 as an adult, which is true and useless
    /// — it is a mistyped year, and letting it through means the one input this
    /// screen exists to check was never checked.
    static let oldestPlausibleAge = 120

    /// What the entered date is, as far as the gate is concerned.
    enum Verdict: Equatable, Sendable {
        /// Still typing. Not an error, and must not be shown as one.
        case incomplete
        /// A date that cannot be a birthdate — impossible, in the future, or
        /// further back than anyone has lived.
        case unreadable
        case underage
        case adult
    }

    /// Reads an entry against a given day.
    ///
    /// `today` is passed in rather than read. An age check that consults the
    /// system clock cannot be tested at its only interesting boundary — the day
    /// someone turns eighteen — and that boundary is the whole function.
    static func verdict(
        for entry: BirthdateEntry,
        on today: Date,
        calendar: Calendar = .current
    ) -> Verdict {
        guard entry.isComplete else { return .incomplete }
        guard let birthdate = entry.date(calendar: calendar) else { return .unreadable }

        let start = calendar.startOfDay(for: birthdate)
        let now = calendar.startOfDay(for: today)
        guard start <= now else { return .unreadable }

        // Whole years elapsed, from the calendar rather than by dividing days.
        // Leap years and unequal month lengths make the arithmetic version
        // wrong by a day for a fraction of birthdays, and the day it is wrong
        // on is a birthday — which is the only day this answer changes.
        let years = calendar.dateComponents([.year], from: start, to: now).year ?? 0
        guard years <= oldestPlausibleAge else { return .unreadable }
        return years >= minimumAge ? .adult : .underage
    }
}

/// Remembers that the gate was passed, on this device and nowhere else.
///
/// A protocol so the record can be driven in a test without reaching for the
/// real defaults, and so the app never writes to a store a test forgot to
/// clean up.
protocol AdultVerificationStore: Sendable {
    var isVerifiedAdult: Bool { get }
    func recordAdult()
}

/// The on-device record.
///
/// Stores the *answer*, never the birthdate. The gate asks a yes/no question
/// once, so keeping the input afterwards would mean holding a date of birth the
/// app has no further use for — and the safest place for data nobody needs is
/// nowhere. Nothing here is ever sent anywhere; there is no network call on
/// this path at all.
///
/// `@unchecked` because `UserDefaults` is not marked `Sendable` and is
/// documented as thread-safe. The unchecked part is that claim, not this type:
/// nothing here holds mutable state of its own.
struct DeviceAdultVerification: AdultVerificationStore, @unchecked Sendable {
    /// Injectable so tests get their own suite rather than the app's.
    let defaults: UserDefaults

    private static let key = "taper.ageGate.verifiedAdult"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Test wiring, and named as such. A UI test needs the gate in front of
        // it on every launch, and the record it leaves behind would otherwise
        // make the second test in a run take a different path from the first.
        // This clears the answer; it never supplies one — the gate still has
        // to be passed for real, which is the difference between resetting a
        // fixture and letting the harness do the product's job.
        //
        // It ships in the release build, which is the risk already on file as
        // `test-wiring-was-compiled-into-the-release-build`. The exposure here
        // is that someone launching with this argument re-answers a question
        // they can already re-answer by reinstalling.
        if ProcessInfo.processInfo.arguments.contains("-TaperForgetAge") {
            defaults.removeObject(forKey: Self.key)
        }
    }

    var isVerifiedAdult: Bool { defaults.bool(forKey: Self.key) }

    func recordAdult() { defaults.set(true, forKey: Self.key) }
}
