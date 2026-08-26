import Foundation
import Observation

/// L8's state: what to offer somebody in the middle of a craving, and what
/// getting through one records.
///
/// The screen is the one place in this app that is not bookkeeping. Everything
/// else asks what happened; this is opened while it is happening, by somebody
/// who wants to use and is trying not to. So it offers the thing that helps
/// before it offers the thing that records — and the recording it does offer
/// costs nothing, because an urge ridden out is not a dose.
@Observable
@MainActor
final class CravingRecord {
    /// Where a "it passed" write is up to.
    ///
    /// `counted` is terminal, and that is the point of it: one craving is one
    /// row, and returning to `resting` would re-enable the button over a screen
    /// that is still open. `failed` does re-enable, because a write that did
    /// not land is worth another try — which leaves the one duplicate no client
    /// can close, the insert that committed and lost its response. That is what
    /// the deferred `request_id` migration is for.
    enum Status: Equatable {
        case resting
        case counting
        case counted
        case failed(String)
    }

    private(set) var status: Status = .resting

    private let store: (any CheckInWriting)?
    private let now: () -> Date

    init(store: (any CheckInWriting)?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// The key to reach for, out of what is actually on the pad.
    ///
    /// A patch is worn and holds a floor; a lozenge or a gum answers a moment.
    /// `TreatmentForm.isPatch` is the app's existing word for that distinction,
    /// and the board's card — "Take your lozenge · 4 mg. This is what it's
    /// for." — is only true of the fast-acting kind. Suggesting a patch to
    /// somebody mid-craving would be advice that does not work on the timescale
    /// they are living in.
    ///
    /// Nil when the pad holds no fast-acting treatment: somebody on a patch
    /// alone, or quitting cold. The screen then has nothing to offer but the
    /// two things that are not a dose, which is honest — inventing a suggestion
    /// out of a patch would be worse than the absence.
    static func suggestion(from pad: Pad) -> StoredPadKey? {
        pad.treatment.first { !$0.form.isWornRatherThanTaken }
    }

    /// Records that a craving passed.
    ///
    /// Returns the row so the day can show it without a re-read — the bargain
    /// every other write in this app makes, for the same reason: a read issued
    /// now can be coalesced behind one already running.
    func itPassed() async -> StoredCheckIn? {
        guard status != .counting, status != .counted else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        status = .counting
        do {
            let stored = try await store.log(.urgePassed(on: now()))
            status = .counted
            return stored
        } catch {
            // Deliberately not "try again" in the way a failed check-in says it.
            // Somebody reading this is mid-craving, and the thing that mattered
            // already happened — the record of it is the part that failed.
            status = .failed("That didn't save. It still counts.")
            return nil
        }
    }

    /// What to call the thing they should get away from.
    ///
    /// The board says "Put the tin away", which is true of a pouch and of
    /// nobody else — a smoker told mid-craving to put a tin away is the app
    /// visibly not knowing who it is talking to. So the noun comes off their
    /// own sources, and mixed sources fall back to the neutral line rather than
    /// guessing which of two they are reaching for.
    static func putAwayTitle(for pad: Pad) -> String {
        let nouns = Set(pad.sources.compactMap(\.thingToPutAway))
        guard nouns.count == 1, let noun = nouns.first else { return "Put it out of reach" }
        return "Put the \(noun) away"
    }

    static let noBackend = "This build has no backend configured, so nothing can be saved."
}

private extension StoredPadKey {
    /// The everyday word for what this source comes in, or nil where there is
    /// no word the app can be sure of.
    var thingToPutAway: String? {
        switch form {
        case .pouch, .dip: return "tin"
        case .vape: return "vape"
        case .cigarette: return "pack"
        // `.other` is a source the user named, and the treatment forms are not
        // what anybody is trying to get away from.
        case .other, .patch, .lozenge, .gum, .inhaler, .spray: return nil
        }
    }
}
