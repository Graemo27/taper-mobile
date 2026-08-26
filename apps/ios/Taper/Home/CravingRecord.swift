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
    enum Status: Equatable {
        case resting
        case counting
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
        guard status != .counting else { return nil }
        guard let store else {
            status = .failed(Self.noBackend)
            return nil
        }

        status = .counting
        do {
            let stored = try await store.log(.urgePassed(on: now()))
            status = .resting
            return stored
        } catch {
            // Deliberately not "try again" in the way a failed check-in says it.
            // Somebody reading this is mid-craving, and the thing that mattered
            // already happened — the record of it is the part that failed.
            status = .failed("That didn't save. It still counts.")
            return nil
        }
    }

    static let noBackend = "This build has no backend configured, so nothing can be saved."
}
