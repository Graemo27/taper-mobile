import Foundation
import Observation

/// The pad, grouped and ordered the way L3 draws it.
///
/// Treatment first, then what the user is quitting. That order is a product
/// decision rather than a query result — the board puts what helps above what
/// hurts — and the read returns the ledgers alphabetically, which is the
/// opposite. Owning it here means the screen never depends on how a `select`
/// happened to sort.
struct Pad: Equatable, Sendable {
    /// The licensed forms someone is tapering with.
    var treatment: [StoredPadKey]
    /// What they are quitting. The board marks this section "counts toward the
    /// ceiling", and it is the only one that does.
    var sources: [StoredPadKey]

    var isEmpty: Bool { treatment.isEmpty && sources.isEmpty }

    init(keys: [StoredPadKey] = []) {
        treatment = Self.inDisplayOrder(keys.filter { $0.ledger == .treatment })
        sources = Self.inDisplayOrder(keys.filter { $0.ledger == .source })
    }

    /// By position, then by id.
    ///
    /// The id is not a tiebreak nobody will hit: `position` has no unique
    /// index — a duplicate is meant to be untidy rather than broken — and two
    /// keys sharing one would otherwise be free to swap between reads. A pad
    /// that reshuffles is a pad nobody builds muscle memory on, which is most
    /// of what a pad is for.
    private static func inDisplayOrder(_ keys: [StoredPadKey]) -> [StoredPadKey] {
        keys.sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }
}

/// What the app knows about the pad.
///
/// An empty pad is `ready`, not a failure: it is what everyone who has not
/// finished onboarding has. Being unable to read one is `unavailable`, and the
/// two must not be conflated — a screen that drew "no keys yet" over a failed
/// read would invite somebody to rebuild a pad that is already there.
enum PadStatus: Equatable, Sendable {
    case loading
    case ready(Pad)
    case unavailable(String)
}

/// Owns the pad the app draws: reading it, and saying why it cannot.
///
/// Separate from `PlanRecord` because the two are read at different moments —
/// the plan before anything is drawn, the pad only once a plan exists — and
/// folding them together would make every launch wait for a screen it may not
/// reach.
@Observable
@MainActor
final class PadRecord {
    private(set) var status: PadStatus = .loading

    /// Nil when the build has no backend, which is distinct from a request
    /// that failed. `PlanRecord` draws the same line for the same reason.
    private let store: (any PadKeyReading)?

    /// One read at a time, for the reason `PlanRecord.isLoading` gives: a
    /// retry sets `loading`, which re-renders, whose `task` starts another —
    /// and a stale failure landing after a fresh success puts the error back
    /// in front of somebody whose pad had just arrived.
    private var isLoading = false

    /// A read asked for while one was already running.
    ///
    /// Remembered rather than dropped. The guard above keeps reads *serial*,
    /// which is all it was ever for — but returning early also threw the
    /// request away, and the request is sometimes the only thing that would
    /// have shown a key that had just been written. A read already in flight
    /// was issued before that write and cannot see it.
    private var wantsAnotherRead = false

    init(store: (any PadKeyReading)?) { self.store = store }

    /// Puts a key the server has just confirmed onto the pad, without re-reading.
    ///
    /// The row comes back from the insert carrying the id and position Postgres
    /// assigned, so this is not a guess about what was written — and `Pad` sorts
    /// by `(position, id)`, so it lands where the next read would have put it.
    ///
    /// A read here would be a second question with a worse answer. `load()`
    /// drops a request that arrives while one is already running, on purpose:
    /// without that guard a retry re-renders, whose `task` starts another read,
    /// and a stale failure lands on top of a fresh success. But it means two
    /// saves close enough together share one read — and if that read was issued
    /// before the second write, the newer key is missing from the pad until
    /// something else reloads it. A key that will not appear after a save that
    /// said it worked is indistinguishable from a save that did not.
    ///
    /// Returns false when there is no pad to add to — mid-load, or after a
    /// failed read — because appending to a state that is not `ready` would
    /// invent one. The caller reloads instead.
    @discardableResult
    func insert(_ key: StoredPadKey) -> Bool {
        guard case let .ready(pad) = status else { return false }
        status = .ready(Pad(keys: pad.treatment + pad.sources + [key]))
        return true
    }

    func load() async {
        guard !isLoading else {
            wantsAnotherRead = true
            return
        }
        isLoading = true
        defer { isLoading = false }

        repeat {
            wantsAnotherRead = false
            await read()
            // Cancellation ends the loop as well as the read: whatever asked
            // for this went away, and a queued repeat would outlive it.
        } while wantsAnotherRead && !Task.isCancelled
    }

    private func read() async {
        guard let store else {
            status = .unavailable(Self.noBackend)
            return
        }

        status = .loading
        do {
            status = .ready(Pad(keys: try await store.currentKeys()))
        } catch {
            // Cancellation is not a failure to report. This read is driven by
            // a view's `task`, so it is cancelled precisely when whatever
            // asked for it went away — and telling somebody their connection
            // is bad because they navigated off the screen is a sentence about
            // nothing that happened. The status stays `loading`, which is what
            // it is: the read never finished, and returning re-runs it.
            //
            // One guard rather than a `catch is CancellationError` beside it.
            // Cancellation arrives by two routes — `CancellationError` from a
            // sleep, `URLError.cancelled` from a request already in flight —
            // and only the second is not a pattern. Asking the flag catches
            // both, and a mutation proved the extra case unreachable.
            guard !Task.isCancelled else { return }
            // One sentence for every failure, as elsewhere: the distinctions
            // the client can draw are not ones the user acts on differently.
            status = .unavailable("Couldn't load your pad. Check your connection and try again.")
        }
    }

    private static let noBackend = "This build has no backend configured, so there is no pad to load."
}
