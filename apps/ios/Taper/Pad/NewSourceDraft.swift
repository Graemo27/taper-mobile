import Foundation
import Observation

/// A source key being added by hand, and the write that saves it.
///
/// Deliberately its own type rather than a mode of `NewKeyDraft`. The rule that
/// separates them is the one the app must not erode: a *treatment* is found in
/// a licensed catalogue, and a *source* is never looked up at all — the user
/// says what they are quitting and the app takes their word. Sharing a type
/// would put a catalogue one field away from the path that must not have one.
///
/// It still exists because the alternative is worse. A source somebody cannot
/// log is a cap that silently lies: every use goes unrecorded, the day looks
/// under the ceiling, and the number the whole app is built on stops meaning
/// anything.
@Observable
@MainActor
final class NewSourceDraft {
    /// Where the draft is up to, so the screen can refuse a second submit and
    /// say what went wrong without inventing a reason.
    enum Status: Equatable {
        case editing
        case saving
        case failed(String)
    }

    private(set) var status: Status = .editing

    /// What they are quitting. Changing it moves the whole strength ladder,
    /// because a pouch and a puff are not measured on the same scale.
    var source: NicotineSource {
        didSet {
            guard source != oldValue else { return }
            strengthIndex = Self.defaultIndex(for: source)
            status = .editing
        }
    }

    private(set) var strengthIndex: Int
    private let store: (any PadKeyWriting)?

    /// The five things somebody can be quitting. `nrt` is absent on purpose:
    /// gum and lozenges are treatments, and the pad files them on the other
    /// ledger through the screen that searches for them.
    static let sources: [NicotineSource] = [.pouches, .vape, .cigarettes, .dip, .other]

    init(source: NicotineSource = .pouches, store: (any PadKeyWriting)?) {
        self.source = source
        self.store = store
        self.strengthIndex = Self.defaultIndex(for: source)
    }

    /// The strengths offered for a source, low to high.
    ///
    /// A ladder rather than a free number, and a different one per source,
    /// because these are not the same size of thing: a pouch is milligrams and
    /// a puff is hundredths of one. A single step would either make the pouch
    /// take twenty presses or put the vape at a figure nobody's device delivers.
    ///
    /// The rungs are what the app already believes. Pouch strengths are the ones
    /// `StrengthOption.pouch` offers during onboarding, so a key added here and
    /// a key seeded there cannot be numbers from different tables. The rest sit
    /// around `NicotineSource.estimatedMgPerUnit`, which is where onboarding's
    /// own figure for them comes from.
    ///
    /// **These are label figures, not delivered dose.** Measured extraction from
    /// commercial pouches ran 38%, 24% and 52%, so no honest conversion exists —
    /// which is the point of the screen's copy saying a rough number is fine.
    /// Logging the same way every day is what makes the trend true; being right
    /// to two decimals about a thing nobody can measure is not on offer.
    static func strengths(for source: NicotineSource) -> [Double] {
        switch source {
        case .pouches: return [2, 3, 4, 6, 8, 10, 12]
        case .cigarettes: return [0.5, 1, 1.5, 2, 2.5]
        case .vape: return [0.05, 0.1, 0.15, 0.2, 0.3, 0.5]
        case .dip: return [1, 2, 3, 4, 5, 6]
        case .nrt, .other: return [0.5, 1, 2, 3, 4, 6, 8]
        }
    }

    /// Where the ladder starts: the figure onboarding would have used, so the
    /// two paths open on the same number rather than at whichever end the list
    /// happens to begin.
    private static func defaultIndex(for source: NicotineSource) -> Int {
        let rungs = strengths(for: source)
        // Pouches print their strength and onboarding asks for it, so there is
        // no estimate to fall back on — 6 mg is the commonest tin, and the
        // board opens on it.
        let wanted = source.estimatedMgPerUnit ?? 6
        return rungs.firstIndex(of: wanted)
            ?? rungs.enumerated().min { abs($0.element - wanted) < abs($1.element - wanted) }?.offset
            ?? 0
    }

    var strengths: [Double] { Self.strengths(for: source) }

    var mg: Double { strengths.indices.contains(strengthIndex) ? strengths[strengthIndex] : 0 }

    /// What the key will say. The source's own name, not a brand — the app has
    /// no catalogue of these and must not appear to.
    var label: String { source.label }

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

    var canSave: Bool { status != .saving && mg > 0 }

    /// Writes the key, and returns it so the pad can show it without a reload.
    ///
    /// Nil means it did not happen and the status says why — the caller keeps
    /// the screen open on a failure rather than throwing the answer away.
    func save() async -> StoredPadKey? {
        guard canSave else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        status = .saving
        do {
            let stored = try await store.add(
                PadKey(form: source.padForm, label: label, mg: mg, position: 0),
                // Never an NDC. Nothing here came from a catalogue, and a key
                // claiming a label it was not built from would be a lie the
                // rest of the app would believe.
                ndc: nil
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
