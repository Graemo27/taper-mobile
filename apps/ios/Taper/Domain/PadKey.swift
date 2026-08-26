import Foundation

/// One key on the pad: a thing the user taps once to log.
///
/// Which ledger a key belongs to is *derived from its form* rather than stored
/// beside it, so a key cannot be built in the state the table's own
/// `pad_keys_form_matches_ledger` check exists to reject.
struct PadKey: Equatable, Sendable {
    /// The two ledgers the pad holds: what someone is quitting, and what they
    /// are treating with. One table separated by a column rather than two
    /// tables, because the pad is one surface and every read would otherwise
    /// be a union.
    enum Ledger: String, Decodable, Sendable {
        case treatment, source
    }

    var form: PadForm
    /// What the key says — the user's own word for the thing, never a brand
    /// the app picked for them.
    var label: String
    /// Label milligrams per unit: per piece, or per 24 hours for a patch. The
    /// number on the box, not what the body absorbs — measured extraction from
    /// commercial pouches ran 38%, 24% and 52%, so no honest conversion exists.
    var mg: Double
    /// Order within its own ledger. The pad draws two groups, not one list, and
    /// the table's index is `(user_id, ledger, position)` to match.
    var position: Int

    var ledger: Ledger { form.ledger }
}

/// The forms a key may take, across both ledgers.
///
/// One enum rather than two, mirroring the single `form` column — and the split
/// back into ledgers is a property of the case, which is what makes the pairing
/// unfalsifiable in the type rather than merely checked in Postgres.
///
/// Inhaler and spray are here because the schema carries them for someone
/// already on one. Onboarding never offers them: both are prescription-only in
/// most of the places this ships.
enum PadForm: String, CaseIterable, Decodable, Sendable {
    case patch, lozenge, gum, inhaler, spray
    case pouch, vape, cigarette, dip, other

    var ledger: PadKey.Ledger {
        switch self {
        case .patch, .lozenge, .gum, .inhaler, .spray: return .treatment
        case .pouch, .vape, .cigarette, .dip, .other: return .source
        }
    }

    /// Whether this form is worn rather than taken when a craving lands.
    ///
    /// `TreatmentForm.isPatch` says the same thing about onboarding's smaller
    /// enum; this is it for the forms a key can actually hold. A patch holds a
    /// floor and a fast-acting form answers a moment, which is why the craving
    /// screen can only offer one of them: suggesting a patch to somebody
    /// mid-craving is advice that does not work on the timescale they are in.
    ///
    /// Sources answer false because the question does not apply to them — they
    /// are what somebody is quitting, not something to reach for.
    var isWornRatherThanTaken: Bool { self == .patch }

    /// What to call this form when it appears beside a label the user chose.
    ///
    /// Sentence case, and never a substitute for the label. The log's rows read
    /// "Nicorette ice mint / Gum · 10:05 am" — the product is what somebody
    /// recognises, and the form is the category it files under.
    ///
    /// `.other` says "Something else", which is what it is: a source with no
    /// case of its own, named by whatever the user typed. Naming it after a
    /// form it is not would put a word in their mouth about what they are
    /// quitting.
    var label: String {
        switch self {
        case .patch: return "Patch"
        case .lozenge: return "Lozenge"
        case .gum: return "Gum"
        case .inhaler: return "Inhaler"
        case .spray: return "Spray"
        case .pouch: return "Pouch"
        case .vape: return "Vape"
        case .cigarette: return "Cigarette"
        case .dip: return "Dip"
        case .other: return "Something else"
        }
    }
}

extension TreatmentForm {
    /// Where a licensed form files on the pad.
    var padForm: PadForm {
        switch self {
        case .patch: return .patch
        case .lozenge: return .lozenge
        case .gum: return .gum
        }
    }
}

extension NicotineSource {
    /// Where a source files on the pad.
    ///
    /// `nrt` lands on `.other`, and it is the one mapping that loses something:
    /// the source ledger's form list is tobacco products, so somebody quitting
    /// licensed gum has no case of their own to sit in. The label still says
    /// exactly what it is and nothing reads `form` for behaviour yet, so the
    /// cost today is nil — but the alternative is widening the check
    /// constraint, which is a migration rather than a mapping.
    var padForm: PadForm {
        switch self {
        case .pouches: return .pouch
        case .cigarettes: return .cigarette
        case .vape: return .vape
        case .dip: return .dip
        case .nrt, .other: return .other
        }
    }
}

extension NicotineReplacement {
    /// The strength this plan gives a form, or nil when it gives it none.
    ///
    /// One accessor rather than two reads of two fields, so the pad and the
    /// screen that recommended the form cannot end up quoting different
    /// numbers for it.
    func strengthMg(for form: TreatmentForm) -> Int? {
        form.isPatch ? patchMg : fastActingMg
    }
}

extension OnboardingAnswers {
    /// The pad as onboarding leaves it: a key for everything the user named.
    ///
    /// Seeded rather than built by hand later, because a pad somebody has to
    /// populate before they can log anything is a pad they meet empty on day
    /// one — and the run has already asked for every field a key needs.
    func padKeys(with replacement: NicotineReplacement) -> [PadKey] {
        sourceKeys() + treatmentKeys(with: replacement)
    }

    /// What they are quitting, in the order the run asked about it.
    private func sourceKeys() -> [PadKey] {
        var keys: [PadKey] = []
        for source in orderedSources {
            // Through `mgPerUnit`, which is the same call `startingCapMg` sums.
            // Not merely the same rule spelled twice: the cap is built from
            // these figures and every log is subtracted from that cap, so a
            // per-unit number that differed here would make the ceiling
            // unreachable or trivially met with nothing on screen to explain
            // it. One function is what makes them unable to disagree.
            //
            // A source with no figure at all is skipped rather than filed at
            // zero — `mg > 0` is a check constraint, and a key at zero would
            // log nothing anyway. `strengthsAreComplete` is what keeps that
            // from reaching a run that got as far as agreeing to a plan.
            guard let mg = mgPerUnit(for: source), mg > 0 else { continue }
            keys.append(PadKey(
                form: source.padForm,
                label: source.label,
                mg: mg,
                position: keys.count
            ))
        }
        return keys
    }

    /// What they chose to taper with, at the strengths the plan committed to.
    private func treatmentKeys(with replacement: NicotineReplacement) -> [PadKey] {
        // No `defersTreatment` guard, deliberately. `deferTreatment()` clears
        // the set, and both it and `treatments` are write-restricted to that
        // pair of methods — so declining already means there is nothing to
        // loop over. A guard here would be a branch no test could reach, which
        // is the shape defects hide in. `decliningIsHonoured` covers the
        // property instead of the branch.
        var keys: [PadKey] = []
        // `allCases` order, not set order: a `Set` has none, and a pad whose
        // keys reshuffle between launches is one nobody builds a habit on.
        for form in TreatmentForm.allCases where treatments.contains(form) {
            // A form the plan has no dose for gets no key. O5a offers all three
            // whatever the plan recommends, so a light intake can tick the
            // patch that was never suggested — and that row is shown with no
            // milligrams on it. Inventing one here to fill a key would be the
            // app recommending a strength it had declined to recommend.
            guard let mg = replacement.strengthMg(for: form) else { continue }
            keys.append(PadKey(
                form: form.padForm,
                label: form.label,
                mg: Double(mg),
                position: keys.count
            ))
        }
        return keys
    }
}
