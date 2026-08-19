import Foundation

/// A licensed form the user can taper with.
///
/// Three, not five. The schema carries inhaler and spray because a user may
/// already be on one, but neither is offered here: both are prescription-only
/// in most of the places this ships, and an option someone cannot obtain is a
/// dead end dressed as a choice.
///
/// This is a fixed list the app names, not a catalogue the user searches. That
/// distinction is the whole of the discovery rule in `AGENTS.md` — nothing a
/// user can browse may return a product we are not licensed to recommend.
enum TreatmentForm: String, CaseIterable, Identifiable, Sendable {
    case patch, lozenge, gum

    var id: String { rawValue }

    var label: String {
        switch self {
        case .patch: return "Patch"
        case .lozenge: return "Lozenge"
        case .gum: return "Gum"
        }
    }

    /// Whether this form is worn rather than taken when a craving lands.
    ///
    /// The two kinds do different jobs — a patch holds a floor, a fast-acting
    /// form answers a moment — which is why the recommended pairing is one of
    /// each rather than two of either.
    var isPatch: Bool { self == .patch }

    /// What the form is *for*, in the words the design uses.
    ///
    /// Never an efficacy claim. Patch and fast-acting forms are interchangeable
    /// on the outcome that matters — RR 0.90 (0.77–1.05), high certainty — so
    /// the honest thing to say about the choice is what each one does, not
    /// which one works better. `dose-response-and-combination-nrt`.
    var role: String {
        switch self {
        case .patch: return "the steady floor"
        case .lozenge: return "for the moment a craving lands"
        case .gum: return "instead of the lozenge"
        }
    }
}

/// What the app suggests someone taper with, and why, given their answers.
///
/// Derived from the plan rather than chosen in the view. Every number on this
/// screen is one the planner already committed to — a patch strength shown here
/// that the plan does not actually use would be a recommendation the product
/// quietly does not stand behind.
struct TreatmentSuggestion: Equatable, Sendable {
    /// The forms recommended, in the order they should read.
    var forms: [TreatmentForm]
    /// The strength for each form, in label milligrams. Absent for a form the
    /// plan has no dose for — a light intake warrants no patch, and showing one
    /// with a strength attached would recommend it by implication.
    var strengthMg: [TreatmentForm: Int]
    /// The user's own answers read back, so the suggestion is visibly a
    /// consequence of what they said rather than a house preference.
    var basis: String
    /// The one claim the screen makes, present only when there is one to make.
    var evidence: String?

    /// Builds the suggestion for a completed run.
    ///
    /// Combination — a patch plus a fast-acting form — is the default rather
    /// than an upgrade, because it is the best-evidenced dosing finding the
    /// product has and the ceiling this product can reach. It drops to a single
    /// fast-acting form only when intake is too light for a patch to be
    /// warranted.
    init(plan: TaperPlan, dailyMg: Double, firstUse: FirstUseOption) {
        let patchMg = plan.replacement.patchMg
        forms = patchMg == nil ? [.lozenge] : [.patch, .lozenge]

        var strengths: [TreatmentForm: Int] = [
            .lozenge: plan.replacement.fastActingMg,
            .gum: plan.replacement.fastActingMg,
        ]
        strengths[.patch] = patchMg
        strengthMg = strengths

        basis = "\(dailyMg.clean) mg a day, first one \(firstUse.recap)."

        // Stated only for the pairing, because that is the comparison the
        // evidence actually makes: combination against a single form, RR 1.27
        // (1.17–1.37) — `dose-response-and-combination-nrt`. A quarter, not a
        // third: the design read the top of the interval as the estimate.
        //
        // Nothing here is a claim about the taper itself. That remains
        // unevidenced, which is why `TaperPlan` carries no success figure for a
        // view to render.
        evidence = patchMg == nil
            ? nil
            : "Two products together beat one alone — about a quarter more people get there."
    }

    /// The headline, naming what is being suggested in plain words.
    var headline: String {
        forms.count > 1 ? "A patch and a lozenge" : "A lozenge"
    }
}
