import Foundation
import Observation

/// What the user is quitting.
///
/// Both licensed forms appear here because someone can arrive already on gum or
/// lozenges and want off them — that is a thing to quit, not a treatment. What
/// they are *treating* with is asked separately, and the two must not be
/// inferred from each other.
enum NicotineSource: String, CaseIterable, Identifiable, Sendable {
    case pouches, cigarettes, vape, dip, nrt, other

    var id: String { rawValue }

    /// Whether "how strong is one?" is a question this source can answer.
    ///
    /// A pouch or a lozenge has a printed per-piece figure. A cigarette does
    /// not — its dose is a property of the cigarette, not a choice — and a vape
    /// is measured in mg/mL against unmeasured puffs. Asking those users to
    /// pick a pouch strength would make them invent a number, and the plan
    /// would then be built on it.
    var usesPerUnitStrength: Bool {
        switch self {
        case .pouches, .nrt: return true
        case .cigarettes, .vape, .dip, .other: return false
        }
    }

    /// The unit this source is counted in, in the words its user already uses.
    ///
    /// Nobody knows their vape in milligrams, so nobody is asked for them.
    /// `modality-shapes-data` is direct about why this matters: whatever a
    /// tracker appears to want, it will get — a milligram field produces an
    /// invented milligram, and the plan is then built on it.
    var unitLabel: String {
        switch self {
        case .pouches: return "Pouches a day"
        case .cigarettes: return "Cigarettes a day"
        case .vape: return "Puffs a day"
        case .dip: return "Packs a day"
        case .nrt: return "Pieces a day"
        case .other: return "Times a day"
        }
    }

    /// How much one tap moves the count. Puffs run to dozens, so stepping them
    /// one at a time would make the honest answer the tedious one.
    var step: Int {
        self == .vape ? 5 : 1
    }

    /// Where the stepper opens. A plausible middle, so the common case is a
    /// nudge rather than a climb from zero.
    var defaultAmount: Int {
        switch self {
        case .vape: return 40
        case .cigarettes: return 10
        case .pouches, .nrt: return 6
        case .dip, .other: return 3
        }
    }

    /// Estimated milligrams per unit, for sources with nothing printed to read.
    ///
    /// Only the cigarette figure has a source: an average cigarette delivers
    /// 1–3 mg and 20 a day absorbs 20–40 mg, so 1.5 is the midpoint consistent
    /// with both (`nicotine-dose-reference`). **The vape and dip figures are
    /// estimates with no source behind them** — the vault holds no
    /// pharmacokinetic data for per-puff or per-portion delivery, which is
    /// filed as G9 under Q12. They are deliberately rough, and that roughness
    /// is part of why the app moves people onto something with a printed
    /// number. Do not present any of these to the user as a measurement.
    var estimatedMgPerUnit: Double? {
        switch self {
        case .cigarettes: return 1.5
        case .vape: return 0.15
        case .dip: return 3
        case .other: return 1
        // Printed on the pack — the user tells us, we do not guess.
        case .pouches, .nrt: return nil
        }
    }

    var label: String {
        switch self {
        case .pouches: return "Pouches"
        case .cigarettes: return "Cigarettes"
        case .vape: return "Vape"
        case .dip: return "Dip or chew"
        case .nrt: return "Nicotine gum or lozenges"
        case .other: return "Something else"
        }
    }
}

/// A strength the user can pick for what they use.
///
/// `mg` is nil for "not sure", which is a deliberate option rather than a gap:
/// the number is on the Drug Facts panel and most people are not holding the
/// tin when they answer. An unsure answer still yields a usable cap — see
/// `OnboardingAnswers.strengthMgPerUnit` — because refusing to proceed until
/// someone fetches a tin is how a run gets abandoned.
struct StrengthOption: Identifiable, Equatable, Sendable {
    let mg: Double?
    let label: String
    /// True when the label names a floor rather than a value — "8 mg or more".
    /// Planning on the floor would size the cap for 8 mg when the pouch might
    /// be 12, and a cap set below what someone actually uses is one they blow
    /// on day one. Failing a schedule was associated with worse outcomes than
    /// never being given one, so this asks for the real number instead.
    var isAtLeast: Bool = false

    var id: String { label }

    /// Strengths pouches are actually sold in.
    static let pouch: [StrengthOption] = [
        StrengthOption(mg: 2, label: "2 mg"),
        StrengthOption(mg: 3, label: "3 mg"),
        StrengthOption(mg: 4, label: "4 mg"),
        StrengthOption(mg: 6, label: "6 mg"),
        StrengthOption(mg: 8, label: "8 mg or more", isAtLeast: true),
        StrengthOption(mg: nil, label: "Not sure"),
    ]

    /// Strengths licensed gum and lozenges are sold in. Separate, because
    /// offering a gum user 3 or 6 mg — pouch strengths their product does not
    /// come in — quietly asks them to fabricate: every option must be an answer
    /// someone could read off a pack.
    static let nrt: [StrengthOption] = [
        StrengthOption(mg: 1, label: "1 mg"),
        StrengthOption(mg: 1.5, label: "1.5 mg"),
        StrengthOption(mg: 2, label: "2 mg"),
        StrengthOption(mg: 4, label: "4 mg"),
        StrengthOption(mg: nil, label: "Not sure"),
    ]

    /// The set to offer for one source. Keyed by source rather than by the
    /// selection as a whole: someone quitting pouches *and* gum has two printed
    /// strengths to give, and answering once for both would apply a 6 mg pouch
    /// to gum that comes in 2 and 4.
    static func options(for source: NicotineSource) -> [StrengthOption] {
        source == .pouches ? pouch : nrt
    }

    /// What an unsure answer is worth for that source — the mid-range pouch, or
    /// the common gum. Named in the helper text, so the screen and the maths
    /// cannot disagree; and always a value from the matching options list,
    /// because an assumption must be an answer the user could have given.
    static func assumedWhenUnsure(for source: NicotineSource) -> Double {
        source == .pouches ? 3 : 2
    }
}

/// How soon after waking the first one happens.
///
/// The single most predictive item in the standard dependence index, which is
/// why `TaperPlanner` treats the earliest band as sufficient for high
/// dependence on its own rather than merely weighting it.
///
/// Each option carries the minutes the planner reasons about, so the wording
/// and the arithmetic cannot drift apart. The values sit inside their band
/// rather than on its edge — 20 for "within 30 minutes" rather than 30 — so a
/// later change to a threshold does not silently reclassify an answer.
struct FirstUseOption: Identifiable, Equatable, Sendable {
    let minutes: Int
    let label: String
    /// The same answer phrased to sit inside a sentence, for the screens that
    /// read a run back to the user. Carried on the option rather than rebuilt
    /// from `minutes`, so the recap cannot describe a band the user did not
    /// pick — the label and the recap are one answer with two wordings.
    let recap: String

    var id: String { label }

    static let all: [FirstUseOption] = [
        FirstUseOption(minutes: 3, label: "It's the first thing I do", recap: "before anything else"),
        FirstUseOption(minutes: 20, label: "Within 30 minutes", recap: "inside 30 minutes of waking"),
        FirstUseOption(minutes: 45, label: "Within an hour", recap: "inside an hour of waking"),
        FirstUseOption(minutes: 180, label: "A few hours in", recap: "a few hours after waking"),
        FirstUseOption(minutes: 360, label: "Afternoon or later", recap: "in the afternoon or later"),
    ]
}

/// Whether the habit survives being ill in bed — the second dependence item.
///
/// A yes/no, given a type rather than left as two literals in the view. The
/// label and the value it stands for are the whole risk here: "Nope!" wired to
/// `true` would score someone a band higher for an answer they did not give,
/// and nothing on screen would look wrong. Pairing them in one value puts the
/// mapping somewhere a test can read it.
struct SickInBedOption: Identifiable, Equatable, Sendable {
    let stillUses: Bool
    let label: String

    var id: Bool { stillUses }

    /// Yes first, matching every other question in the run: the more dependent
    /// answer leads, so the list reads as a scale rather than a coin toss.
    static let all: [SickInBedOption] = [
        SickInBedOption(stillUses: true, label: "Yep"),
        SickInBedOption(stillUses: false, label: "Nope!"),
    ]
}

/// Everything onboarding collects, accumulated as the user moves through it.
///
/// One object rather than a value threaded screen to screen: the run branches —
/// a quit date is optional, and O5a only appears once a treatment is relevant —
/// so screens need to read answers given several steps earlier.
///
/// Deliberately holds answers, not a plan. Turning these into a taper is
/// `TaperPlanner`'s job, and keeping that boundary means the plan stays a pure
/// function of stated inputs rather than something the UI can nudge.
@Observable
final class OnboardingAnswers {
    var sources: Set<NicotineSource> = []
    /// The printed strength given for each source that has one.
    var strengths: [NicotineSource: StrengthOption] = [:]
    /// The exact figure per source, once an open-ended option is narrowed down.
    var exactStrengths: [NicotineSource: Double] = [:]
    /// How much of each source, in that source's own unit.
    var amounts: [NicotineSource: Int] = [:]
    /// How soon after waking the first one happens (O4).
    var firstUse: FirstUseOption?
    /// Whether they use it while ill in bed (O5). Optional because unanswered
    /// and "no" are different states, and only one of them may reach the plan.
    var usesWhenIllInBed: Bool?

    /// True once the user has said enough for the run to continue.
    var hasChosenSources: Bool { !sources.isEmpty }

    /// The licensed forms chosen to taper with (O5a). Several, because the
    /// recommended shape is a patch plus a fast-acting form rather than one
    /// product.
    /// Write-restricted, unlike the other answers here. The two O5a answers
    /// contradict each other, and that invariant lives in `toggle(_:)` and
    /// `deferTreatment()` — a direct insert would walk straight past it and
    /// leave the run holding both.
    private(set) var treatments: Set<TreatmentForm> = []
    /// True when the user chose to start without a treatment.
    ///
    /// Not the same as an empty `treatments`, which only means the question is
    /// unanswered. Someone who has actively declined has told us something, and
    /// the app owes them a run that proceeds rather than a screen that waits.
    private(set) var defersTreatment = false

    /// The moments they reach for one (O7).
    ///
    /// Deliberately not gated, and the only question in the run that is not.
    /// Nothing downstream requires a trigger, and someone whose moments are not
    /// on the list would otherwise have to tick one that is false to get past
    /// the screen — which is the same fabrication the strength and amount
    /// screens are built to avoid, in categorical form.
    ///
    /// An empty set therefore means "none of these", "none at all" and "did not
    /// say" alike. That is acceptable here precisely because nothing reads it
    /// as a number: all three produce the same behaviour, which is no
    /// personalisation.
    private(set) var triggers: Set<Trigger> = []

    /// What they have already tried (O8).
    ///
    /// Write-restricted: "never really tried" excludes every other answer, and
    /// that invariant lives in `toggle(_:)`.
    private(set) var priorAttempts: Set<PriorAttempt> = []

    /// The clock, injected rather than read.
    ///
    /// A date question needs to know what day it is, and a suite that cannot
    /// control that either guesses or drifts. Nothing else in the model reads
    /// the current time.
    var now: () -> Date = { Date() }

    /// The chosen quit date (O10), or nil for a run holding where it is.
    var quitDate: Date?

    /// Whether the run ends at a date or holds where it is (O9).
    ///
    /// Optional because unanswered is not the same as choosing to reduce, and
    /// only one of those may decide whether the next screen is shown.
    var planShape: PlanShape?

    /// True once O5 has an answer either way.
    ///
    /// On the model rather than in the view because it is the gate on Continue,
    /// and an ungated Continue here is invisible: the user walks past the
    /// question, `usesWhenIllInBed` stays nil, and the run reaches the plan
    /// preview with an input that can never resolve. Nothing looks wrong until
    /// the last screen has nothing to show.
    var hasAnsweredSickInBed: Bool { usesWhenIllInBed != nil }

    /// The strength to plan with for one source, in label milligrams.
    ///
    /// Nil only while that source's question is unanswered. Once answered it
    /// always resolves to a number, because "not sure" is an answer — it means
    /// "use the middle of the range and let me correct it later", not "stop".
    func strengthMgPerUnit(for source: NicotineSource) -> Double? {
        guard let option = strengths[source] else { return nil }
        if let exact = exactStrengths[source], option.isAtLeast { return exact }
        return option.mg ?? StrengthOption.assumedWhenUnsure(for: source)
    }

    /// What one of a source is worth, whichever way that figure was arrived at.
    ///
    /// The single answer to "how much is one?", because two callers need it and
    /// they must never disagree: the cap is built by summing this across
    /// sources, and the pad subtracts from that cap using the same figure per
    /// key. A per-unit number that differed between the two would make a cap
    /// unreachable or trivially met, and nothing on screen would show why.
    ///
    /// Something the user told us beats something the app estimated. Today no
    /// source can have both — only pouches and NRT are ever asked for a printed
    /// strength, and neither carries an estimate — so the order is unobservable
    /// and this is a statement of intent for the day that changes.
    func mgPerUnit(for source: NicotineSource) -> Double? {
        strengthMgPerUnit(for: source) ?? source.estimatedMgPerUnit
    }

    /// True when that source's strength is an assumption rather than something
    /// read off a pack. The app owes the user a chance to correct it, and a
    /// number it invented must not be presented as one they gave.
    func strengthIsAssumed(for source: NicotineSource) -> Bool {
        guard let option = strengths[source] else { return false }
        if option.mg == nil { return true }
        // A floor that has not been narrowed down is still an assumption, and
        // the least safe kind: it under-states rather than over-states.
        return option.isAtLeast && exactStrengths[source] == nil
    }

    /// The sources still owing a number before the run can continue.
    var sourcesNeedingExactStrength: [NicotineSource] {
        orderedSources.filter { source in
            (strengths[source]?.isAtLeast ?? false) && exactStrengths[source] == nil
        }
    }

    /// Every source that should be asked for a printed strength.
    var sourcesWithPrintedStrength: [NicotineSource] {
        orderedSources.filter(\.usesPerUnitStrength)
    }

    /// The sources to ask about, in a stable order. A `Set` has none, and rows
    /// that reshuffle between renders are unusable.
    var orderedSources: [NicotineSource] {
        NicotineSource.allCases.filter { sources.contains($0) }
    }

    func amount(for source: NicotineSource) -> Int {
        amounts[source] ?? source.defaultAmount
    }

    func setAmount(_ value: Int, for source: NicotineSource) {
        amounts[source] = max(0, value)
    }

    /// The starting daily figure the planner works from.
    ///
    /// An index rather than a dose, and knowingly so. Pouches contribute label
    /// milligrams off the pack; everything else contributes an estimate, and
    /// two of those estimates have no source (Q12/G9). Summing across products
    /// is already an index rather than a measurement per
    /// `label-dose-is-not-delivered-dose`; summing across *bases* — label for
    /// one, estimated delivery for another — is a second mixing on top.
    ///
    /// It is accepted because the alternative is asking people for numbers they
    /// do not have, and because the roughness applies only to the sources the
    /// app is steering them off anyway. It must never be shown as a precise
    /// figure.
    var startingCapMg: Double {
        orderedSources.reduce(0) { total, source in
            total + (mgPerUnit(for: source) ?? 0) * Double(amount(for: source))
        }
    }

    /// True once every source that prints a strength has one that resolves.
    ///
    /// Guards a quiet failure rather than a visible one. `startingCapMg` folds
    /// an unanswered source in as zero, so a run naming both cigarettes and
    /// pouches has a positive cap from the cigarettes alone — a number that
    /// looks complete and silently leaves out a product the user named. A cap
    /// short by a whole source is a cap they blow in the first week.
    var strengthsAreComplete: Bool {
        sourcesWithPrintedStrength.allSatisfy { strengthMgPerUnit(for: $0) != nil }
            && sourcesNeedingExactStrength.isEmpty
    }

    /// What the planner needs, or nil while any of it is still unanswered.
    ///
    /// Optional on purpose. Every field here is something the user said, and
    /// there is no default that would not be an invention — "no" to the
    /// sick-in-bed question is an answer, and its absence is not the same
    /// thing. Returning nil keeps the run from producing a plan built partly
    /// on values nobody supplied, which is the failure this whole flow has
    /// been shaped to avoid.
    ///
    /// `weeksUntilQuitDate` stays nil legitimately: a reduction-only run has
    /// no date, and the planner treats that as a supported state rather than
    /// a missing answer.
    var taperInput: TaperInput? { taperInput(asOf: now()) }

    /// The same input, reckoned against a day the caller has already read.
    ///
    /// A screen that needs both the plan and a date derived from it has to
    /// build them from one reading of the clock. Two readings can straddle
    /// midnight, and the plan then covers a runway that ends a day away from
    /// the date printed beside it.
    func taperInput(asOf today: Date) -> TaperInput? {
        guard let firstUse, let usesWhenIllInBed,
              strengthsAreComplete, startingCapMg > 0 else { return nil }
        return TaperInput(
            startingCapMg: startingCapMg,
            minutesToFirstUse: firstUse.minutes,
            usesWhenIllInBed: usesWhenIllInBed,
            weeksUntilQuitDate: weeksUntilQuitDate(asOf: today)
        )
    }

    /// Weeks of runway to the chosen date, or nil for a reduction-only run.
    ///
    /// Nil is a supported state rather than a missing answer — most nicotine
    /// users are not ready to name a date, and inventing one for them is the
    /// product addressing the wrong person.
    var weeksUntilQuitDate: Int? { weeksUntilQuitDate(asOf: now()) }

    /// The same runway, reckoned against a day the caller has already read.
    func weeksUntilQuitDate(asOf today: Date) -> Int? {
        guard planShape?.needsQuitDate == true, let quitDate else { return nil }
        return QuitDate.weeks(from: today, to: quitDate)
    }

    /// What O10 says about the date currently chosen, or nil before there is
    /// one to describe.
    var quitDateSummary: QuitDateSummary? {
        // The runway is read back off the input rather than recomputed. Both
        // paths call the clock, and between two calls the day can turn over —
        // which would have the planner working from one number while the
        // sentence under the date quotes another.
        guard let input = taperInput, let weeks = input.weeksUntilQuitDate else { return nil }
        return QuitDateSummary(
            plan: TaperPlanner.plan(for: input),
            requestedWeeks: weeks,
            startingCapMg: input.startingCapMg
        )
    }

    /// The earliest date the picker may offer.
    ///
    /// The start of today, not this instant. `DatePicker` compares `Date`
    /// instants even when it is only showing days, so a bound of "now" makes
    /// today unselectable from one minute past midnight onward — the user sees
    /// today greyed out with no explanation. Today is a legitimate answer:
    /// `QuitDate.weeks` reads it as a week of runway rather than as zero.
    func earliestQuitDate(calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now())
    }

    /// Settles on a date to show when the picker opens.
    ///
    /// Keeps a date the user already chose, because they chose it — going back
    /// to change an earlier answer should not silently discard a later one.
    /// Replaces it only when it has gone stale: a date picked before a detour
    /// through the rest of the run can be in the past by the time they return,
    /// and the picker cannot even display it.
    func settleQuitDate() {
        if let quitDate, quitDate >= earliestQuitDate() { return }
        quitDate = defaultQuitDate()
    }

    /// The date to open the picker on: the soonest the plan can actually
    /// reach. A default the user's own answers cannot satisfy would start them
    /// on a stretch warning before they have chosen anything.
    func defaultQuitDate() -> Date {
        // The descent floor for this run's dependence — the soonest date the
        // plan can reach without being stretched past it.
        let weeks = taperInput
            .map { TaperPlanner.minimumWeeks(for: TaperPlanner.plan(for: $0).dependence) }
            ?? TaperPlanner.minimumWeeks(for: .moderate)
        return QuitDate.date(weeksFrom: now(), weeks: weeks)
    }

    func toggle(_ source: NicotineSource) {
        if sources.contains(source) {
            sources.remove(source)
        } else {
            sources.insert(source)
        }
        // A strength for a deselected source must not survive into the plan.
        // The routing skips the screen for such runs, so a stale value would
        // never be shown or corrected — just used.
        strengths = strengths.filter { sources.contains($0.key) }
        exactStrengths = exactStrengths.filter { sources.contains($0.key) }
        amounts = amounts.filter { sources.contains($0.key) }
    }

    /// Picks or unpicks a treatment form.
    ///
    /// Choosing one cancels a previous "not right now", because the two are
    /// contradictory answers to the same question and holding both would let
    /// the run continue on whichever the next screen happened to read.
    func toggle(_ form: TreatmentForm) {
        if treatments.contains(form) {
            treatments.remove(form)
        } else {
            treatments.insert(form)
        }
        defersTreatment = false
    }

    /// Whether a step has anything to ask, given what has been said so far.
    ///
    /// On the answers rather than in the flow because a skipped screen is
    /// invisible from the outside: nothing renders, nothing errors, and the
    /// only evidence is a question the user was never asked. Here it can be
    /// asserted directly.
    func shouldAsk(_ step: OnboardingStep) -> Bool {
        switch step {
        case .strength:
            // A per-piece question. A run naming only cigarettes or a vape has
            // no per-piece figure to give, and asking anyway would make them
            // invent one for the plan to be built on.
            return sources.contains { $0.usesPerUnitStrength }
        case .quitDate:
            // Someone who said "date later" has already declined. Showing the
            // picker anyway would ask them to decline a second time, which
            // reads as the app not having listened.
            return planShape?.needsQuitDate ?? false
        default:
            return true
        }
    }

    /// Picks or unpicks something tried before.
    ///
    /// "Never really tried" clears everything else and is cleared by anything
    /// else, from either direction. The two are contradictory answers to one
    /// question, and holding both would let a later screen read whichever it
    /// happened to look at first.
    func toggle(_ attempt: PriorAttempt) {
        if priorAttempts.contains(attempt) {
            priorAttempts.remove(attempt)
        } else if attempt.isNone {
            priorAttempts = [attempt]
        } else {
            priorAttempts.remove(.neverTried)
            priorAttempts.insert(attempt)
        }
    }

    /// True once O8 has an answer. Unlike the triggers screen, this one can
    /// gate: "never really tried" is on the list, so someone with nothing to
    /// report has a true answer to give rather than an empty one.
    var hasAnsweredPriorAttempts: Bool { !priorAttempts.isEmpty }

    /// Picks or unpicks a trigger. No exclusivity to keep here — the moments
    /// are independent, and most people have several.
    func toggle(_ trigger: Trigger) {
        if triggers.contains(trigger) {
            triggers.remove(trigger)
        } else {
            triggers.insert(trigger)
        }
    }

    /// The triggers in a stable order. A `Set` has none, and rows that
    /// reshuffle between renders are unusable.
    var orderedTriggers: [Trigger] {
        Trigger.allCases.filter { triggers.contains($0) }
    }

    /// Records that the user is starting without a treatment, clearing anything
    /// picked before. Same reason as above, from the other side.
    func deferTreatment() {
        treatments.removeAll()
        defersTreatment = true
    }

    /// True once O5a has an answer — a form, or an explicit decision to go
    /// without. Silence is neither.
    var hasAnsweredTreatment: Bool { !treatments.isEmpty || defersTreatment }

    /// The run said back to the user on O6, or nil while it is incomplete.
    var startingLine: StartingLine? {
        guard let input = taperInput, let firstUse else { return nil }
        return StartingLine(
            plan: TaperPlanner.plan(for: input),
            dailyMg: input.startingCapMg,
            firstUse: firstUse
        )
    }

    /// The finished plan as O11 shows it, or nil while the run is incomplete.
    ///
    /// One clock read, shared by the plan and by the date on its last
    /// milestone. Taking two would let a run that crosses midnight between them
    /// print a countdown that does not reach the day beside it.
    ///
    /// Gated on `hasAnsweredTreatment` as well as on the planner's inputs. An
    /// empty `treatments` set means "has not said", not "said no" — and the
    /// preview reads the two the same way, so an unanswered run would be told
    /// it has nothing to come off. The gate belongs here rather than on the
    /// screen before it: a rule enforced only by a view is one no test can see.
    var planPreview: PlanPreview? {
        let today = now()
        guard hasAnsweredTreatment, let input = taperInput(asOf: today) else { return nil }
        return PlanPreview(
            plan: TaperPlanner.plan(for: input),
            today: today,
            treatments: treatments
        )
    }

    /// What to suggest on O5a, or nil while the answers it rests on are
    /// incomplete. The suggestion restates the user's own figures, so a
    /// half-answered run has nothing honest to put on the screen.
    var treatmentSuggestion: TreatmentSuggestion? {
        guard let input = taperInput, let firstUse else { return nil }
        return TreatmentSuggestion(
            plan: TaperPlanner.plan(for: input),
            dailyMg: input.startingCapMg,
            firstUse: firstUse
        )
    }
}
