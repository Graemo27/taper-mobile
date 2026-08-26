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

    /// Writes the check-in, and hands the row up so the day can fold it in.
    func log() async -> StoredCheckIn? {
        guard status != .logging, status != .logged else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        status = .logging
        do {
            let stored = try await store.log(.product(
                brand: product.brand, form: product.form,
                mg: mg, quantity: quantity, on: now()
            ))
            status = .logged
            return stored
        } catch {
            status = .failed("Couldn't log that. Try again.")
            return nil
        }
    }

    // MARK: - What the screen says

    /// "Stop smoking aid · FDA OTC monograph" — what every product the
    /// catalogue can return is, by the rule that put it there.
    var subtitleText: String { "Stop smoking aid · FDA OTC monograph" }

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
    /// names it.
    var ingredientHeading: String { "Active ingredient (per \(unitWord))" }

    /// "2 pieces", "1 patch" — the count in the unit the form comes in.
    var quantityText: String {
        "\(quantity) \(quantity == 1 ? unitWord : unitPlural)"
    }

    /// "4 mg" — what this check-in will record, strength times count.
    var totalText: String { "\((mg * Double(quantity)).clean) mg" }

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
