import Foundation
import Observation

/// L1's daily check-in: today's one-word answer, and the saving of it.
///
/// The card is optional and must feel it. Answers are written optimistically —
/// the chip fills the moment it is tapped, and is put back if the write fails —
/// because a judgement this small should not have a spinner. Tapping the
/// selected word again takes the answer back: "skip freely" includes changing
/// your mind about having answered at all.
@Observable
@MainActor
final class DayRatingRecord {
    /// Today's answer as this screen believes it, shown selected on the card.
    private(set) var rating: DayRating?
    /// The save that did not land, said quietly under the chips.
    private(set) var failureText: String?

    private var isSaving = false
    private let store: (any DayRatingStoring)?
    private let day: () -> Date

    init(store: (any DayRatingStoring)?, day: @escaping () -> Date = Date.init) {
        self.store = store
        self.day = day
    }

    /// Reads today's answer, quietly.
    ///
    /// A failed read leaves the card unanswered rather than posting an error:
    /// this is the one optional surface on home, and a card that nags about
    /// not knowing the answer to an optional question has made it mandatory.
    /// The write path is an upsert, so acting on a stale blank is harmless.
    func load() async {
        guard let store, !isSaving else { return }
        rating = (try? await store.rating(on: day())) ?? rating
    }

    /// Answers, or un-answers when the tapped word is already the answer.
    func tapped(_ tapped: DayRating) async {
        guard !isSaving else { return }
        guard let store else {
            failureText = Self.noBackend
            return
        }

        let before = rating
        let clearing = tapped == before
        rating = clearing ? nil : tapped
        failureText = nil
        isSaving = true
        defer { isSaving = false }

        do {
            if clearing {
                try await store.clearRating(on: day())
            } else {
                try await store.rate(tapped, on: day())
            }
        } catch {
            // The optimistic answer was a claim about the server, and the
            // server said no — putting it back is what keeps the card honest.
            rating = before
            failureText = "Couldn't save that. Try again."
        }
    }

    static let noBackend = "This build has no backend configured, so nothing can be saved."
}

extension DayRating {
    /// The chip's word. "So-so" gets its hyphen back here — the raw value is a
    /// wire token, and the hyphen belongs to the screen.
    var word: String {
        switch self {
        case .easy: return "Easy"
        case .soSo: return "So-so"
        case .rough: return "Rough"
        }
    }
}
