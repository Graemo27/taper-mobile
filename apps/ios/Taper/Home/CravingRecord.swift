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
    /// Which of the screen's two writes a status is about. They end the same
    /// way — a row, and the screen closing — but a dose that failed to record
    /// is a different sentence from a craving that did.
    enum Write: Equatable {
        case take
        case count
    }

    /// Where the screen's write is up to.
    ///
    /// `logged` is terminal, and that is the point of it: one craving is one
    /// row, and returning to `resting` would re-arm a button over a screen that
    /// is still open. `failed` does re-enable, because a write that did not
    /// land is worth another try — which leaves the one duplicate no client can
    /// close, the insert that committed and lost its response. That is what the
    /// deferred `request_id` migration is for.
    enum Status: Equatable {
        case resting
        case working(Write)
        case logged(Write)
        case failed(Write, String)
    }

    private(set) var status: Status = .resting

    private let store: (any CheckInWriting)?
    private let now: () -> Date

    init(store: (any CheckInWriting)?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    /// Presentation identity. The record's life is the screen's: a new craving
    /// gets a new one, which is what keeps a spent `logged` from being
    /// presented again.
    let id = UUID()

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
    /// out of a patch would be worse than the absence. A pad still loading or
    /// unread answers the same way, for the same reason.
    static func suggestion(from pad: Pad?) -> StoredPadKey? {
        pad?.treatment.first { !$0.form.isWornRatherThanTaken }
    }

    /// Records that a craving passed.
    func itPassed() async -> StoredCheckIn? {
        await write(.count, .urgePassed(on: now()))
    }

    /// Records the treatment the screen suggested, the way the pad would.
    ///
    /// Written here rather than through the pad's own selection: that selection
    /// is a count somebody may be halfway through tapping out on another tab,
    /// and borrowing it to log one lozenge would either clobber it or send it.
    func take(_ key: StoredPadKey) async -> StoredCheckIn? {
        await write(.take, CheckInDraft(pending: PendingEntry(key: key), day: now()))
    }

    /// Returns the row so the day can show it without a re-read — the bargain
    /// every other write in this app makes, for the same reason: a read issued
    /// now can be coalesced behind one already running.
    private func write(_ kind: Write, _ draft: CheckInDraft) async -> StoredCheckIn? {
        switch status {
        case .working, .logged: return nil
        case .resting, .failed: break
        }
        guard let store else {
            status = .failed(kind, Self.noBackend)
            return nil
        }

        status = .working(kind)
        do {
            let stored = try await store.log(draft)
            status = .logged(kind)
            return stored
        } catch {
            status = .failed(kind, Self.message(for: kind))
            return nil
        }
    }

    /// A count that failed is deliberately not asked to retry: somebody reading
    /// it is mid-craving, and the thing that mattered already happened — the
    /// record of it is the part that failed. A dose is the other way round. It
    /// is a real milligram against a real cap, and a log that quietly drops it
    /// is a cap that lies.
    private static func message(for kind: Write) -> String {
        switch kind {
        case .count: return "That didn't save. It still counts."
        case .take: return "Couldn't log that. Try again."
        }
    }

    /// What to call the thing they should get away from.
    ///
    /// The board says "Put the tin away", which is true of a pouch and of
    /// nobody else — a smoker told mid-craving to put a tin away is the app
    /// visibly not knowing who it is talking to. So the noun comes off their
    /// own sources, and mixed sources fall back to the neutral line rather than
    /// guessing which of two they are reaching for.
    static func putAwayTitle(for pad: Pad?) -> String {
        let nouns = Set((pad?.sources ?? []).compactMap(\.thingToPutAway))
        guard nouns.count == 1, let noun = nouns.first else { return "Put it out of reach" }
        return "Put the \(noun) away"
    }

    /// Whether a write is in flight, so neither button starts a second one.
    var isWriting: Bool {
        if case .working = status { return true }
        return false
    }

    /// Whether this screen has already written its row.
    var isSpent: Bool {
        if case .logged = status { return true }
        return false
    }

    static let noBackend = "This build has no backend configured, so nothing can be saved."
}

extension CravingRecord: Identifiable {}

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
