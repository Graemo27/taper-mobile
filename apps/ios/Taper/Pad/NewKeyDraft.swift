import Foundation
import Observation

/// A treatment key being made from a search result, and the write that saves it.
///
/// The strength is chosen from the ones the product actually comes in rather
/// than typed. A free number and an NDC disagree the moment somebody steps 4 mg
/// to 5 on a lozenge sold at 2 and 4 — the key would claim a dose the label it
/// cites does not carry. Stepping through the licensed strengths keeps the
/// number and the product it came from describing the same thing.
@Observable
@MainActor
final class NewKeyDraft {
    /// Where the draft is up to, so the screen can refuse a second submit and
    /// say what went wrong without inventing a reason.
    enum Status: Equatable {
        case editing
        case saving
        case failed(String)
    }

    private(set) var status: Status = .editing

    /// What the key will say. Prefilled from the catalogue and then the user's,
    /// because the pad shows their word for the thing rather than a brand the
    /// app picked.
    var name: String

    /// Which of the five licensed forms this is. Prefilled from the result, and
    /// changeable — a product found under one form is still the user's to
    /// classify.
    var form: PadForm {
        didSet { if form != oldValue { status = .editing } }
    }

    /// The strengths the product is sold at, low to high, each with the NDC that
    /// supplies it.
    let strengths: [(mg: Double, ndc: String)]
    private(set) var strengthIndex: Int

    private let product: NRTResult
    private let store: (any PadKeyWriting)?

    init(product: NRTResult, store: (any PadKeyWriting)?) {
        self.product = product
        self.store = store
        self.strengths = product.strengths.sorted { $0.mg < $1.mg }
        // The lowest, not the first. Somebody arriving at a taper screen is
        // reducing, and the smaller dose is the one that needs no defending.
        self.strengthIndex = 0
        self.form = product.form
        self.name = "\(product.brand) \(product.form.label.lowercased())"
    }

    var mg: Double { strengths.indices.contains(strengthIndex) ? strengths[strengthIndex].mg : 0 }

    /// The catalogue's identifier for the exact product, or nil once the draft
    /// has stopped describing it.
    ///
    /// Dropped when the form is changed, because an NDC names one product of one
    /// form — keeping it would file the key under a label that describes
    /// something else. The name is not treated the same way: it is expected to
    /// be edited, and "Nicorette lozenge, mint" is still that lozenge.
    var ndc: String? {
        guard form == product.form, strengths.indices.contains(strengthIndex) else { return nil }
        return strengths[strengthIndex].ndc
    }

    var canLower: Bool { strengthIndex > 0 }
    var canRaise: Bool { strengthIndex + 1 < strengths.count }

    func lower() {
        guard canLower else { return }
        strengthIndex -= 1
        status = .editing
    }

    func raise() {
        guard canRaise else { return }
        strengthIndex += 1
        status = .editing
    }

    /// What the label will be once saved. Trimmed here rather than at the column,
    /// which refuses blank and anything past 60.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the key can be written at all. A name of spaces is not a name,
    /// and the table would refuse it as a failed insert rather than as advice.
    var canSave: Bool {
        status != .saving && !trimmedName.isEmpty && trimmedName.count <= Self.nameLimit && mg > 0
    }

    /// Matches `pad_keys.label`'s check, so the screen can say so before the
    /// round trip rather than after it.
    static let nameLimit = 60

    /// Writes the key, and returns it so the pad can show it without a reload.
    ///
    /// Nil means it did not happen and the status says why — the caller keeps
    /// the screen open on a failure, because closing it would throw away
    /// everything typed to reach that point.
    func save() async -> StoredPadKey? {
        guard canSave else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        status = .saving
        do {
            let stored = try await store.add(
                PadKey(form: form, label: trimmedName, mg: mg, position: 0),
                ndc: ndc
            )
            status = .editing
            return stored
        } catch {
            status = .failed("Couldn't add that key. Check your connection and try again.")
            return nil
        }
    }

    static let noBackend = "This build has no backend configured, so nothing can be saved."
}
