import Foundation

/// What the plan was on a day that has already happened.
///
/// The log draws every past day's meter against *that day's* ceiling, and the
/// current plan cannot answer for one: `taper_plans` is a single upserted row,
/// so the moment somebody re-plans, last week's cap is gone. Versions keep it,
/// and this is the reader.
struct PlanHistory {
    /// Newest first, which is the order the store returns and the order this
    /// reads in: the version covering a day is the first one starting on or
    /// before it.
    private let versions: [StoredPlanVersion]
    private let calendar: Calendar

    init(versions: [StoredPlanVersion], calendar: Calendar = .current) {
        self.versions = versions.sorted { $0.effectiveFrom > $1.effectiveFrom }
        self.calendar = calendar
    }

    /// The first day any version covered, or nil when there are none.
    ///
    /// The taper's beginning, which is a different question from the current
    /// plan's `cap_effective_from` once somebody has re-planned: that column
    /// moves with the latest version, and this does not. It is what tells the
    /// log there is nothing earlier worth offering to load.
    var planStart: Date? {
        versions
            .compactMap { PlanDay.date(from: $0.effectiveFrom, calendar: calendar) }
            .map { calendar.startOfDay(for: $0) }
            .min()
    }

    /// The ceiling in force on a day, or nil when no plan covered it.
    ///
    /// Nil is a real answer and not a zero. A day before the plan began has no
    /// ceiling — drawing it as zero would render every check-in on it as
    /// infinitely over, which is a bar the colour of failure across somebody's
    /// first week.
    func cap(on day: Date) -> Double? {
        guard let version = version(covering: day),
              let start = PlanDay.date(from: version.effectiveFrom, calendar: calendar)
        else { return nil }

        // The week is counted from the version's own start, not from the
        // taper's. That is what a re-plan means: the descent begins again from
        // where the person actually is, and `current_cap_mg` on that version is
        // week zero of it.
        let elapsed = max(0, calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: day)
        ).day ?? 0)

        // Refused rather than treated as absent, the same way `PlanProgress`
        // refuses it — and for a sharper reason here. `flatMap` would read an
        // unreadable date as "no quit date", which is a different and flatter
        // schedule, so this would hand back a plausible ceiling for a day it
        // could not actually work out. That screen has no way to look wrong.
        //
        // Written out in both places rather than shared: the two callers refuse
        // differently — one abandons the whole plan, one abandons a single day
        // — and the only shape that unifies them is a double optional, which
        // reads worse than the four lines it saves.
        let quitDate: Date?
        switch version.quitDate {
        case let .some(wire):
            guard let parsed = PlanDay.date(from: wire, calendar: calendar) else { return nil }
            quitDate = parsed
        case .none:
            quitDate = nil
        }
        let schedule = TaperPlanner.plan(for: TaperInput(
            startingCapMg: version.startingCapMg,
            minutesToFirstUse: version.firstUseMinutes,
            usesWhenIllInBed: version.sickInBed,
            weeksUntilQuitDate: quitDate.map {
                QuitDate.weeks(from: start, to: $0, calendar: calendar)
            }
        )).weeklyCapsMg

        return TaperCap.inForce(
            pinned: version.currentCapMg,
            schedule: schedule,
            week: elapsed / 7
        )
    }

    /// The version a day was lived under: the last one to start on or before
    /// it.
    ///
    /// A version that starts *after* the day is a plan the person had not made
    /// yet, so it cannot have been what they were measured against — which is
    /// the whole reason this type exists rather than reading the current row.
    private func version(covering day: Date) -> StoredPlanVersion? {
        let asked = calendar.startOfDay(for: day)
        return versions.first { version in
            guard let start = PlanDay.date(from: version.effectiveFrom, calendar: calendar) else {
                return false
            }
            return calendar.startOfDay(for: start) <= asked
        }
    }
}

/// The one rule for turning a pinned cap and a descent into the ceiling that
/// actually applies.
///
/// Shared by today's picture and by every past day rather than written twice.
/// The two disagreeing would put one number on the home screen and a different
/// one on the same day in the log, which is the single thing this app cannot
/// afford to get wrong.
enum TaperCap {
    /// The pinned figure or the descent's, whichever is lower.
    ///
    /// A pin is a cap and the day it began applying, and nothing advances it —
    /// so the row stops being current the moment its week ends, and honouring
    /// it alone would read 18 mg on day fifty-five of a taper to zero. Taking
    /// the lower keeps what the pin was for: a plan stretched, or a cap
    /// corrected by hand, must never *raise* a ceiling somebody is already
    /// living under.
    static func inForce(pinned: Double, schedule: [Double], week: Int) -> Double {
        // Clamped to the last week rather than falling back to the pin. Past
        // the end of the descent the plan has reached zero, and the pinned
        // figure is the one number that is certainly wrong there.
        guard let last = schedule.indices.last else { return pinned }
        return min(pinned, schedule[min(week, last)])
    }
}
