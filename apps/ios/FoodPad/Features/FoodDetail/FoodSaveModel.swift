import Foundation

@MainActor
/// Save-to-today state, keyed by food id so "Saved" can never confirm a
/// different food. Confirmation holds 2.4s, then reverts.
final class FoodSaveModel: ObservableObject {
    enum Status: Equatable { case idle, saving, saved, failed }

    @Published private var activeID: Int?
    @Published private var activeStatus: Status = .idle
    private let persist: @Sendable (JournalDraft) async throws -> Void
    private let holdConfirmation: @Sendable () async -> Void
    private var generation = 0

    init(
        save: @escaping @Sendable (JournalDraft) async throws -> Void,
        holdConfirmation: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .milliseconds(2_400))
        }
    ) {
        persist = save
        self.holdConfirmation = holdConfirmation
    }

    func status(for fdcID: Int) -> Status {
        activeID == fdcID ? activeStatus : .idle
    }

    func reset(for fdcID: Int) {
        guard activeID == fdcID, activeStatus != .saving else { return }
        generation += 1
        activeStatus = .idle
    }

    func save(_ draft: JournalDraft) async {
        guard status(for: draft.fdcID) != .saving else { return }
        generation += 1
        let request = generation
        activeID = draft.fdcID
        activeStatus = .saving
        do {
            try await persist(draft)
            guard generation == request else { return }
            activeStatus = .saved
            await holdConfirmation()
            guard generation == request, activeID == draft.fdcID else { return }
            activeStatus = .idle
        } catch {
            guard generation == request else { return }
            activeStatus = .failed
        }
    }
}
