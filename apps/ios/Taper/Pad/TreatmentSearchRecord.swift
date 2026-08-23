import Foundation
import Observation

/// What the search knows: what was typed, and what came back.
///
/// Empty results and a failed lookup are different states, because one of them
/// has a retry and the other is an answer.
enum SearchStatus: Equatable, Sendable {
    /// Nothing typed yet — the field is open and waiting.
    case resting
    case searching
    case results([NRTResult])
    /// The catalogue answered, and had nothing.
    case noMatches
    case unavailable(String)
}

/// Runs a search of the licensed catalogue and holds what it found.
///
/// One search at a time, and only the newest one counts: typing is faster than
/// a round trip, so an earlier request landing after a later one would put the
/// results for "nico" under the word "nicorette".
@Observable
@MainActor
final class TreatmentSearchRecord {
    private(set) var status: SearchStatus = .resting
    /// What is in the field. Held here so the view has no state of its own and
    /// the two cannot disagree about what was searched for.
    var query = "" {
        didSet { if query != oldValue { schedule() } }
    }

    private let search: (any NRTSearching)?
    /// How long to wait after a keystroke before asking.
    ///
    /// A search per character would send six requests for "nicorette" and show
    /// the answer to whichever landed last. Short enough that it still feels
    /// like typing.
    private let debounce: Duration
    private var inFlight: Task<Void, Never>?
    /// Which search is current. An older one that finishes late compares this
    /// and drops its own answer — the same identity check the day's records
    /// needed, for the same reason.
    private var generation = 0

    init(search: (any NRTSearching)?, debounce: Duration = .milliseconds(300)) {
        self.search = search
        self.debounce = debounce
    }

    /// Puts the field back to resting, cancelling anything in flight.
    func clear() {
        inFlight?.cancel()
        generation += 1
        query = ""
        status = .resting
    }

    private func schedule() {
        inFlight?.cancel()
        generation += 1
        let mine = generation

        let asked = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else {
            status = .resting
            return
        }

        guard let search else {
            status = .unavailable(Self.noBackend)
            return
        }

        status = .searching
        inFlight = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }

            do {
                let results = try await search.search(asked)
                // Only the newest search may answer. An older one landing late
                // would put the results for "nico" under the word "nicorette".
                guard generation == mine else { return }
                status = results.isEmpty ? .noMatches : .results(results)
            } catch {
                guard !Task.isCancelled, generation == mine else { return }
                status = .unavailable("Couldn't reach the product list. Check your connection.")
            }
        }
    }

    static let noBackend = "This build has no backend configured, so nothing can be looked up."
}
