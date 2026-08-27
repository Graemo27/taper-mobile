import Foundation
import Observation

/// L3e's state: which keys are being removed, and what went wrong if one wasn't.
///
/// Editing is a mode of the pad rather than a screen over it. The keys stay
/// where they are and grow a way to delete themselves, because the thing being
/// edited is the arrangement — moving it somewhere else would ask somebody to
/// remember a layout while they changed it.
@Observable
@MainActor
final class PadEditRecord {
    /// Whether the pad is showing its edit affordances.
    private(set) var isEditing = false

    /// Keys with a delete in flight. A set rather than one id, because two
    /// taps on two keys are both legitimate and neither should wait for the
    /// other.
    private(set) var removing: Set<Int> = []

    /// The last removal that failed, and which key it was.
    ///
    /// Carries the id so the message can sit on the key it is about. One
    /// failure at a time is enough — a second replaces it, because the note
    /// says what to do rather than enumerating what went wrong.
    private(set) var failure: Failure?

    /// Whether an arrangement is being written. Read by the pad so a second
    /// drag cannot start on top of the first — two arrangements in flight
    /// would land in whichever order the network chose.
    private(set) var isReordering = false

    /// A removal that did not happen, named by the key it was for.
    struct Failure: Equatable {
        let keyID: Int
        let message: String
    }

    private let store: (any PadKeyWriting)?

    init(store: (any PadKeyWriting)?) {
        self.store = store
    }

    func startEditing() {
        isEditing = true
        failure = nil
    }

    /// Leaves edit mode.
    ///
    /// Refused while anything is still being removed: "Done" that closed over a
    /// delete in flight would put the pad back with a key on it that is about
    /// to vanish, which reads as the tap having done nothing.
    func finishEditing() {
        guard removing.isEmpty else { return }
        isEditing = false
        failure = nil
    }

    var canFinish: Bool { removing.isEmpty }

    /// Whether this key is mid-removal, so the pad can dim it rather than let
    /// it be tapped twice.
    func isRemoving(_ id: Int) -> Bool { removing.contains(id) }

    /// Removes a key, and reports whether the pad should drop it.
    ///
    /// Returns the id on success so the caller can take it off the pad without
    /// a re-read — the same bargain `add` makes, for the same reason: a read
    /// issued now can be coalesced behind one already running.
    func remove(_ id: Int) async -> Int? {
        guard !removing.contains(id) else { return nil }
        guard let store else {
            failure = Failure(keyID: id, message: Self.noBackend)
            return nil
        }

        removing.insert(id)
        defer { removing.remove(id) }
        // Cleared on the way in rather than only on success: a stale message
        // beside a key somebody is retrying reads as the retry having failed
        // before it finished.
        if failure?.keyID == id { failure = nil }

        do {
            try await store.remove(id)
            return id
        } catch {
            failure = Failure(keyID: id, message: "Couldn't remove that key. Try again.")
            return nil
        }
    }

    /// Persists an arrangement, and says whether it stuck.
    ///
    /// The pad has already moved when this is called — a drag that waited for
    /// the server before the key followed the finger would feel broken — so a
    /// false here means the caller must put it back. It does not report which
    /// key failed, because a reorder does not fail per key: the whole
    /// arrangement lands or none of it does.
    func reorder(_ ids: [Int]) async -> Bool {
        guard let store else {
            // Its own sentence: `noBackend` says nothing can be *removed*,
            // which is a true statement about a different button.
            failure = Failure(keyID: ids.first ?? 0, message: Self.noBackendForOrder)
            return false
        }
        isReordering = true
        defer { isReordering = false }
        failure = nil

        do {
            _ = try await store.reorder(ids)
            return true
        } catch {
            failure = Failure(keyID: ids.first ?? 0, message: Self.orderNotSaved)
            return false
        }
    }

    static let noBackend = "This build has no backend configured, so nothing can be removed."

    /// Says the pad went back, because it did — the alternative is somebody
    /// believing an arrangement they cannot see is saved.
    static let orderNotSaved = "Couldn't save that order. The pad's back as it was."

    static let noBackendForOrder =
        "This build has no backend configured, so nothing can be rearranged."
}
