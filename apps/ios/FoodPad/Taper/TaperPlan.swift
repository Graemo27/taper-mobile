import Foundation

/// What onboarding learns, reduced to the four numbers a plan is built from.
///
/// Weeks rather than dates on purpose: calendar arithmetic is the caller's
/// problem, and keeping it out here makes the whole generator a pure function
/// with no clock, no time zone and nothing to stub.
struct TaperInput {
    /// Label milligrams a day across every source, from O3.
    var startingCapMg: Double
    /// Minutes from waking to the first use, from O4.
    var minutesToFirstUse: Int
    /// Whether they use it while ill in bed, from O5.
    var usesWhenIllInBed: Bool
    /// Weeks until the chosen quit date, or nil for reduction with no date.
    var weeksUntilQuitDate: Int?
}

/// How dependent someone is, on the two items that carry most of the signal.
///
/// Time to first use of the day is the strongest single item in the standard
/// index, which is why it can reach `high` on its own.
enum Dependence {
    case low, moderate, high
}

/// The licensed NRT a plan recommends alongside the descent.
///
/// Combination — a patch plus a fast-acting form — is the ceiling this product
/// can reach and beats either alone, so it is the default rather than an
/// upgrade. `patchMg` is nil only for intakes too light to warrant one.
struct NicotineReplacement {
    var patchMg: Int?
    var fastActingMg: Int
}

/// A descending daily ceiling, the treatment that supports it, and the caveats.
///
/// Deliberately exposes no success rate or confidence figure. A taper is a
/// small, uncertain, probably-not-harmful benefit rather than an established
/// one, so there is no number here for a view to turn into a promise.
struct TaperPlan {
    var dependence: Dependence
    var replacement: NicotineReplacement
    /// The ceiling for each week, starting with this one. Ends at zero when a
    /// quit date is in play, and holds flat when one is not.
    var weeklyCapsMg: [Double]
    /// Set when the requested quit date was sooner than the descent floor, and
    /// carries what was asked for so the app can say the plan was stretched.
    var stretchedFromRequestedWeeks: Int?
    /// True when an intake far above what heavy cigarette use delivers suggests
    /// a data-entry error rather than a heavy user.
    var intakeLooksImplausible: Bool

    var reachesZero: Bool { weeklyCapsMg.last == 0 }
}

/// Turns onboarding answers into a plan.
///
/// The rules here are clinical parameters rather than UI preferences, and each
/// is anchored in the vault: patch strength follows intake the way licensed
/// labelling does; fast-acting strength follows dependence, because 4 mg beats
/// 2 mg for dependent users and does nothing for light ones; and the descent
/// rate is bounded because being given a schedule and failing it was associated
/// with worse outcomes than never receiving one.
enum TaperPlanner {
    /// Above this, a stated intake is more likely a mis-entry than a habit —
    /// twenty cigarettes a day is 20–40 mg absorbed.
    private static let implausibleDailyMg: Double = 100

    static func plan(for input: TaperInput) -> TaperPlan {
        let dependence = dependence(for: input)
        let replacement = replacement(for: input, dependence: dependence)
        let implausible = input.startingCapMg > implausibleDailyMg

        guard input.startingCapMg > 0 else {
            return TaperPlan(
                dependence: dependence,
                replacement: replacement,
                weeklyCapsMg: [],
                stretchedFromRequestedWeeks: nil,
                intakeLooksImplausible: implausible
            )
        }

        // No date is a supported state, not an unfinished one. Most nicotine
        // users are not ready to quit, and inventing a deadline for them is the
        // product addressing the wrong person — so the cap holds where they are
        // and the app waits to be asked.
        guard let requested = input.weeksUntilQuitDate else {
            return TaperPlan(
                dependence: dependence,
                replacement: replacement,
                weeklyCapsMg: Array(repeating: input.startingCapMg, count: 5),
                stretchedFromRequestedWeeks: nil,
                intakeLooksImplausible: implausible
            )
        }

        let floor = minimumWeeks(for: dependence)
        let weeks = max(requested, floor)

        return TaperPlan(
            dependence: dependence,
            replacement: replacement,
            weeklyCapsMg: descent(from: input.startingCapMg, over: weeks),
            stretchedFromRequestedWeeks: weeks > requested ? requested : nil,
            intakeLooksImplausible: implausible
        )
    }

    // MARK: - Dependence

    private static func dependence(for input: TaperInput) -> Dependence {
        var score = 0

        switch input.minutesToFirstUse {
        case ..<6: score += 3
        case ..<31: score += 2
        case ..<61: score += 1
        default: break
        }

        switch input.startingCapMg {
        case 30...: score += 3
        case 20..<30: score += 2
        case 10..<20: score += 1
        default: break
        }

        if input.usesWhenIllInBed { score += 1 }

        switch score {
        case ...2: return .low
        case 3...4: return .moderate
        default: return .high
        }
    }

    // MARK: - Dose

    private static func replacement(
        for input: TaperInput,
        dependence: Dependence
    ) -> NicotineReplacement {
        // Patch strength tracks intake, matching how the licensed products are
        // labelled. Capped at 21 mg deliberately: above it there is no clear
        // gain and considerably worse tolerability, so a very heavy intake must
        // not scale the patch with it.
        let patch: Int?
        switch input.startingCapMg {
        case 20...: patch = 21
        case 10..<20: patch = 14
        default: patch = nil
        }

        // Fast-acting strength tracks dependence instead, because that is where
        // the 4 mg advantage was found — and where it was absent.
        return NicotineReplacement(patchMg: patch, fastActingMg: dependence == .high ? 4 : 2)
    }

    // MARK: - The descent

    /// The shortest descent each dependence level may be given.
    ///
    /// A dependent user is not allowed the steep curve a light one can manage.
    /// Duration carries no evidence of harm, so stretching is free where
    /// compressing is not.
    private static func minimumWeeks(for dependence: Dependence) -> Int {
        switch dependence {
        case .high: return 7
        case .moderate: return 5
        case .low: return 4
        }
    }

    private static func descent(from start: Double, over weeks: Int) -> [Double] {
        (0...weeks).map { week in
            guard week > 0 else { return start }
            guard week < weeks else { return 0 }
            // Rounded to the half-milligram: a cap is something someone counts
            // pouches against, and 14.4 is not a number anyone can act on.
            let raw = start * (1 - Double(week) / Double(weeks))
            return (raw * 2).rounded() / 2
        }
    }
}
