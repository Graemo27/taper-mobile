import Foundation
import Testing
@testable import Taper

/// A catalogue that answers on command, and counts what it was asked.
///
/// Every field is behind the lock, not only the tally. `search` is nonisolated
/// and runs on whatever thread the task lands on, while the test that started
/// it is still on the main actor setting up the next answer — Thread Sanitizer
/// reports the unguarded version as a real race, not a theoretical one.
private final class FakeCatalogue: NRTSearching, @unchecked Sendable {
    /// Everything `search` consults, as one value, so a call can take a
    /// consistent snapshot in a single acquisition rather than reading four
    /// properties a test may be part-way through changing.
    private struct Answers {
        var results: [String: [NRTResult]] = [:]
        var fails = false
        var delay: Duration?
        var ignoresCancellation = false
        var asked: [String] = []
    }

    private let lock = NSLock()
    private var state = Answers()

    var results: [String: [NRTResult]] {
        get { lock.withLock { state.results } }
        set { lock.withLock { state.results = newValue } }
    }
    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var delay: Duration? {
        get { lock.withLock { state.delay } }
        set { lock.withLock { state.delay = newValue } }
    }
    /// Finishes even after the task is cancelled, which is what a request
    /// already on the wire does: cancellation is cooperative, and a call past
    /// its last suspension point returns a perfectly good answer to a question
    /// nobody is asking any more.
    var ignoresCancellation: Bool {
        get { lock.withLock { state.ignoresCancellation } }
        set { lock.withLock { state.ignoresCancellation = newValue } }
    }
    var asked: [String] { lock.withLock { state.asked } }

    func search(_ query: String) async throws -> [NRTResult] {
        let answers = lock.withLock {
            state.asked.append(query)
            return state
        }
        if let delay = answers.delay {
            if answers.ignoresCancellation {
                // Yielding rather than sleeping, because a cancelled
                // `Task.sleep` returns at once — which would make the stale
                // answer arrive *first* and be harmlessly overwritten. The race
                // only exists when the overtaken request lands last.
                let deadline = Date().addingTimeInterval(delay.seconds)
                while Date() < deadline { await Task.yield() }
            } else {
                try await Task.sleep(for: delay)
            }
        }
        if answers.fails { throw URLError(.notConnectedToInternet) }
        return answers.results[query] ?? []
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

private func result(_ brand: String, _ mg: Double...) -> NRTResult {
    NRTResult(brand: brand, labeler: "nicotine polacrilex", form: .gum,
              strengths: mg.map { (mg: $0, ndc: "\(brand)-\($0)") })
}

/// Covers the search the pad runs against the licensed catalogue: what it asks,
/// when, and which answer it is allowed to believe.
@MainActor
struct TreatmentSearchTests {
    private func record(_ catalogue: FakeCatalogue) -> TreatmentSearchRecord {
        TreatmentSearchRecord(search: catalogue, debounce: .milliseconds(40))
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { await Task.yield() }
        #expect(condition(), "the condition never became true")
    }

    @Test("typing a word does not send a request per letter")
    func aSearchWaitsForAPause() async {
        // Six requests for "nicorette" is six round trips and six answers, and
        // the one that lands last wins rather than the one that is right.
        let catalogue = FakeCatalogue()
        catalogue.results["nic"] = [result("Nicorette", 2, 4)]
        let record = record(catalogue)

        // Spaced out, because typing is. Assigning three times in one turn
        // proves nothing: each assignment cancels the last before it can run,
        // so the letters never reach the catalogue whether there is a debounce
        // or not. Real keystrokes arrive far enough apart to fire.
        record.query = "n"
        try? await Task.sleep(for: .milliseconds(15))
        record.query = "ni"
        try? await Task.sleep(for: .milliseconds(15))
        record.query = "nic"
        await waitUntil { catalogue.asked == ["nic"] }

        #expect(catalogue.asked == ["nic"], "it asked about the letters on the way")
    }

    @Test("an older answer does not overwrite a newer one")
    func theSearchBelievesOnlyItsOwnAnswer() async {
        // Typing outruns the network. An earlier request landing late would put
        // the results for a prefix under the whole word — the same identity
        // problem the day's records had, in the one place where the user is
        // actively changing the question.
        let catalogue = FakeCatalogue()
        catalogue.results["nic"] = [result("Wrong", 1)]
        catalogue.results["nicorette"] = [result("Nicorette", 2, 4)]
        catalogue.delay = .milliseconds(300)
        // The slow request survives being cancelled, which is the only way this
        // race is real: a cancelled task whose network call has already
        // committed still comes back with an answer, and something has to
        // refuse it.
        catalogue.ignoresCancellation = true

        let record = record(catalogue)
        record.query = "nic"
        await waitUntil { catalogue.asked == ["nic"] }

        catalogue.delay = nil
        record.query = "nicorette"
        await waitUntil {
            if case let .results(rows) = record.status { return rows.first?.brand == "Nicorette" }
            return false
        }

        // Let the slow one land.
        try? await Task.sleep(for: .milliseconds(400))
        guard case let .results(rows) = record.status else {
            Issue.record("the search lost its results")
            return
        }
        #expect(rows.first?.brand == "Nicorette", "a stale answer overwrote the current one")
    }

    @Test("an empty catalogue is an answer, not a failure")
    func nothingFoundIsNotSomethingBroken() async {
        // One of these has a retry and the other does not, and telling somebody
        // to check their connection when the catalogue simply has no Zonnic is
        // how they stop believing the errors that matter.
        let catalogue = FakeCatalogue()
        let record = record(catalogue)

        record.query = "zzzz"
        await waitUntil { record.status == .noMatches }

        #expect(record.status == .noMatches)
    }

    @Test("a lookup that fails says so, and does not read as empty")
    func aBrokenLookupIsNotAnEmptyShelf() async {
        let catalogue = FakeCatalogue()
        catalogue.fails = true
        let record = record(catalogue)

        record.query = "nicorette"
        await waitUntil {
            if case .unavailable = record.status { return true }
            return false
        }

        guard case let .unavailable(message) = record.status else {
            Issue.record("a failed lookup did not reach the unavailable state")
            return
        }
        #expect(message.contains("connection"))
        #expect(!message.contains("URLError"))
    }

    @Test("emptying the field asks nothing and says nothing")
    func aClearedFieldIsNotASearchForNothing() async {
        let catalogue = FakeCatalogue()
        catalogue.results["nic"] = [result("Nicorette", 2)]
        let record = record(catalogue)

        record.query = "nic"
        await waitUntil { catalogue.asked == ["nic"] }

        record.query = "   "
        #expect(record.status == .resting, "whitespace was treated as a search")
        #expect(catalogue.asked == ["nic"], "it asked the catalogue about nothing")
    }

    @Test("cancelling puts the field back and forgets what was in flight")
    func cancellingLeavesNothingBehind() async {
        let catalogue = FakeCatalogue()
        catalogue.results["nic"] = [result("Nicorette", 2)]
        let record = record(catalogue)

        record.query = "nic"
        await waitUntil {
            if case .results = record.status { return true }
            return false
        }

        record.clear()
        #expect(record.query.isEmpty)
        #expect(record.status == .resting)
    }
}
