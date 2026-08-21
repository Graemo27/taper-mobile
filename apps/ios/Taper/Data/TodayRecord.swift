import Foundation
import Observation

/// What the app knows about today's log.
///
/// An empty day is `ready` and empty — that is how every day starts. Being
/// unable to read it is `unavailable`, and the two must not be conflated: a
/// screen showing "nothing logged yet" over a failed read would invite somebody
/// to log a second time against a day it could not see.
enum DayStatus: Equatable, Sendable {
    case loading
    case ready
    case unavailable(String)
}

/// Owns today: what has been logged, and what is selected against it.
///
/// Writing a tap is the next thing; this reads the day the write will land on
/// and folds the pending selection into the same tally, so the figure on screen
/// is one number rather than two views of one.
///
/// The day is read through a closure rather than captured once. An app left
/// open across midnight should roll over on its own — "new day, new cap;
/// yesterday stays in yesterday" — and a record holding a stale `Date` would
/// keep adding to a day that ended hours ago.
@Observable
@MainActor
final class TodayRecord {
    private(set) var entries: [StoredCheckIn] = []
    private(set) var status: DayStatus = .loading
    /// What is chosen on the pad. Held here rather than beside it, because the
    /// tally is the one place the day and the selection have to be read
    /// together, and two owners would make that a join at every call site.
    let selection: PadSelection

    private let store: (any CheckInStoring)?
    private let day: () -> Date
    private var isLoading = false

    init(
        store: (any CheckInStoring)?,
        selection: PadSelection = PadSelection(),
        day: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.selection = selection
        self.day = day
    }

    /// Today, with the pending selection folded in, measured against the cap
    /// the plan gives.
    ///
    /// The ceiling is passed rather than held, so this type never needs to know
    /// about the plan — and the one number both screens quote comes from a
    /// single place.
    func tally(ceilingMg: Double) -> TodaysTally {
        TodaysTally(entries: entries, pending: selection.pending, ceilingMg: ceilingMg)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let store else {
            status = .unavailable(Self.noBackend)
            return
        }

        status = .loading
        do {
            entries = try await store.entries(on: day())
            status = .ready
        } catch {
            // Abandoned, not failed. This read is driven by a view's `task`, so
            // it is cancelled exactly when somebody navigates away, and
            // reporting that would put "check your connection" in front of a
            // connection that was fine. The flag rather than a `catch is
            // CancellationError`, because a request already in flight arrives
            // as `URLError.cancelled` and only the flag covers both routes.
            guard !Task.isCancelled else { return }
            status = .unavailable("Couldn't load today. Check your connection and try again.")
        }
    }

    private static let noBackend = "This build has no backend configured, so there is no log to read."
}
