import Foundation
import Observation

/// L5's state: one catalogue product, a chosen strength and count, and the
/// check-in they become.
///
/// The screen exists for the Drug Facts panel — the label is the only honest
/// source for what a piece contains — and its write is the one door that logs
/// a treatment without a key: somebody using a product they never put on
/// their pad still gets to record it, because a dose that cannot be logged is
/// a log that quietly lies.
@Observable
@MainActor
final class ProductDetailRecord {
    /// Where the write is up to. `logged` is terminal for `CravingRecord`'s
    /// reason: the screen outlives its row, and a button that re-arms over a
    /// spent screen files the same dose twice.
    enum Status: Equatable {
        case resting
        case logging
        case logged
        case failed(String)
    }

    let product: NRTResult
    private(set) var status: Status = .resting
    /// The strength in hand, defaulting to the lowest — this is a tapering
    /// app, and the presumptuous default is the one that presumes less.
    private(set) var mg: Double
    private(set) var quantity = 1

    private let store: (any CheckInWriting)?
    private let now: () -> Date

    init(product: NRTResult, store: (any CheckInWriting)?, now: @escaping () -> Date = Date.init) {
        self.product = product
        self.store = store
        mg = product.strengths.map(\.mg).min() ?? 0
        self.now = now
    }

    func choose(_ strength: Double) {
        guard product.strengths.contains(where: { $0.mg == strength }) else { return }
        mg = strength
    }

    /// Clamped to what the column accepts, `PendingEntry`'s rule: a number the
    /// database would reject should never have been buildable on a screen.
    func add(_ delta: Int) {
        quantity = min(max(quantity + delta, PendingEntry.quantityRange.lowerBound),
                       PendingEntry.quantityRange.upperBound)
    }

    /// Whether this label's number is a dose that can be counted.
    ///
    /// False for a spray: openFDA carries its strength as a concentration —
    /// Nicotrol NS is 10 mg per mL, and one actuation delivers about 0.5 mg —
    /// so multiplying the catalogue's number by a count of sprays would
    /// record twenty times the dose. The screen offers the facts and not the
    /// write; the pad's own type-and-mg path is where a spray gets logged,
    /// with a per-dose strength the user enters.
    var isCountable: Bool { product.form != .spray && mg > 0 }

    /// Why there is no count and no button, when there is a reason to give.
    ///
    /// Two reasons, two sentences: a spray's label lists a concentration,
    /// and a label with no stated strength has no number to count at all. A
    /// zero would be worse than either — a keyless zero-milligram treatment
    /// row is the exact shape the day reads back as a craving outlasted, so
    /// logging one would file a dose as an urge.
    var uncountableNote: String? {
        if product.form == .spray { return Self.sprayNote }
        if mg <= 0 { return Self.noStrengthNote }
        return nil
    }

    /// Writes the check-in, and hands the row up so the day can fold it in.
    func log() async -> StoredCheckIn? {
        guard isCountable else { return nil }
        
        guard status != .logging, status != .logged else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        guard let draft = CheckInDraft.product(
            brand: product.brand, form: product.form,
            mg: mg, quantity: quantity, on: now()
        ) else { return nil }

        status = .logging
        do {
            let stored = try await store.log(draft)
            status = .logged
            return stored
        } catch {
            status = .failed("Couldn't log that. Try again.")
            return nil
        }
    }

    // MARK: - What the screen says

    /// "Stop smoking aid · From the FDA label library" — what every product
    /// the catalogue can return is, by the rule that put it there. Not "OTC
    /// monograph": the catalogue also carries prescription NRT — Nicotrol's
    /// inhaler and spray are NDA products — and the result does not say which
    /// it is, so the screen does not claim to know.
    var subtitleText: String { "Stop smoking aid · From the FDA label library" }

    /// "Nicotine polacrilex 2 mg" — the label's own name for the active
    /// ingredient. Polacrilex is the resin form in gum and lozenges; the
    /// patch, inhaler and spray deliver plain nicotine.
    var activeIngredientText: String {
        switch product.form {
        case .gum, .lozenge: return "Nicotine polacrilex \(mg.clean) mg"
        default: return "Nicotine \(mg.clean) mg"
        }
    }

    /// "Active ingredient (per piece)" — the unit named the way the label
    /// names it. A spray's number is a concentration, not a per-spray dose,
    /// so its heading claims no unit.
    var ingredientHeading: String {
        isCountable ? "Active ingredient (per \(unitWord))" : "Active ingredient (as labeled)"
    }

    /// Why a spray offers no count and no button, said on the screen.
    static let sprayNote = """
        This label lists nicotine as a concentration, not a per-spray dose, \
        so it can't be counted here. Add it to your pad with the per-dose \
        strength from your pharmacist, and log it from there.
        """

    /// The other reason a label cannot be counted: it names no strength.
    static let noStrengthNote = """
        This label doesn't state a strength, so there is no number to log. \
        Add it to your pad with the strength from its packaging, and log it \
        from there.
        """

    /// "2 pieces", "1 patch" — the count in the unit the form comes in. Nil
    /// where counting means nothing, so no caller can dress a concentration
    /// or a missing strength as a dose.
    var quantityText: String? {
        guard isCountable else { return nil }
        return "\(quantity) \(quantity == 1 ? unitWord : unitPlural)"
    }

    /// "4 mg" — what this check-in will record, strength times count.
    var totalText: String? {
        guard isCountable else { return nil }
        return "\((mg * Double(quantity)).clean) mg"
    }

    /// The label's one-line usage fact, said under the count.
    ///
    /// These are the OTC label's own directions compressed to a clause, not
    /// medical advice invented here — the gum is chewed, the lozenge
    /// dissolves, the patch is worn.
    var usageText: String {
        switch product.form {
        case .gum: return "Chewed ~30 min each"
        case .lozenge: return "Dissolves in 20–30 min"
        case .patch: return "One worn through the day"
        case .inhaler: return "Puffed as needed"
        default: return "As the label directs"
        }
    }

    private var unitWord: String {
        switch product.form {
        case .gum, .lozenge: return "piece"
        case .patch: return "patch"
        case .spray: return "spray"
        case .inhaler: return "cartridge"
        default: return "dose"
        }
    }

    private var unitPlural: String {
        switch product.form {
        case .gum, .lozenge: return "pieces"
        case .patch: return "patches"
        case .spray: return "sprays"
        case .inhaler: return "cartridges"
        default: return "doses"
        }
    }

    /// Only a failure is shown, and a retry is invited — unlike the craving
    /// screen's count, a dose is a real milligram and dropping it quietly
    /// would be the log lying.
    var failureText: String? {
        if case let .failed(message) = status { return message }
        return nil
    }

    static let noBackend = "This build has no backend configured, so nothing can be logged."
}
