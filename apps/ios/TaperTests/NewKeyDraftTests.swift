import Foundation
import Testing
@testable import Taper

/// A store that answers on command and records what it was asked to write.
private final class FakeAdder: PadKeyWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var state = Written()

    private struct Written {
        var added: [(key: PadKey, ndc: String?)] = []
        var fails = false
    }

    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var added: [(key: PadKey, ndc: String?)] { lock.withLock { state.added } }

    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey] { [] }

    func add(_ key: PadKey, ndc: String?) async throws -> StoredPadKey {
        let shouldFail = lock.withLock {
            state.added.append((key, ndc))
            return state.fails
        }
        if shouldFail { throw URLError(.notConnectedToInternet) }
        return StoredPadKey(id: 1, form: key.form, label: key.label,
                            mg: key.mg, position: key.position, ndc: ndc)
    }
}

private func product(_ brand: String, _ form: PadForm, _ mg: Double...) -> NRTResult {
    NRTResult(brand: brand, labeler: "GSK", form: form,
              strengths: mg.map { (mg: $0, ndc: "\(brand)-\($0)") })
}

/// Covers the key being made from a search result: what it starts as, which
/// strengths it will accept, and what it writes.
@MainActor
struct NewKeyDraftTests {
    @Test("a draft starts as the product it came from")
    func theResultFillsTheForm() {
        let draft = NewKeyDraft(product: product("Nicorette", .lozenge, 4, 2), store: nil)

        #expect(draft.form == .lozenge)
        #expect(draft.name == "Nicorette lozenge")
        // The lowest, not the first in the array — somebody on a taper screen
        // is reducing, and the strengths arrived unsorted here on purpose.
        #expect(draft.mg == 2)
    }

    @Test("the strength steps through what the product is sold at")
    func theStepperCannotInventADose() {
        // A free number and an NDC disagree the moment somebody steps 4 mg to 5
        // on a lozenge sold at 2 and 4: the key would claim a dose the label it
        // cites does not carry.
        let draft = NewKeyDraft(product: product("Nicorette", .lozenge, 2, 4), store: nil)

        #expect(draft.canLower == false, "it started somewhere it could go below")
        #expect(draft.mg == 2)

        draft.raise()
        #expect(draft.mg == 4)
        #expect(draft.canRaise == false, "the stepper went past the strongest one sold")

        draft.raise()
        #expect(draft.mg == 4, "raising past the end moved the dose anyway")

        draft.lower()
        #expect(draft.mg == 2)
    }

    @Test("the NDC follows the strength, so the number and the label agree")
    func eachStrengthCarriesItsOwnLabel() {
        let draft = NewKeyDraft(product: product("Nicorette", .lozenge, 2, 4), store: nil)

        #expect(draft.ndc == "Nicorette-2.0")
        draft.raise()
        #expect(draft.ndc == "Nicorette-4.0", "the key cited the label for a different dose")
    }

    @Test("changing the form drops the NDC rather than misfiling the key")
    func aChangedFormIsNoLongerThatProduct() {
        // An NDC names one product of one form. Keeping it through a form change
        // would file the key under a label describing something else.
        let draft = NewKeyDraft(product: product("Nicorette", .lozenge, 4), store: nil)
        #expect(draft.ndc != nil)

        draft.form = .gum
        #expect(draft.ndc == nil, "a gum key kept a lozenge's NDC")

        draft.form = .lozenge
        #expect(draft.ndc == "Nicorette-4.0", "going back did not restore the label")
    }

    @Test("a name of spaces is not a name")
    func theTableWouldRefuseItSoTheScreenDoesFirst() {
        // `pad_keys.label` refuses blank and anything past 60. Asking first
        // makes it advice rather than a failed insert.
        let draft = NewKeyDraft(product: product("Nicorette", .gum, 2), store: FakeAdder())
        #expect(draft.canSave)

        draft.name = "   "
        #expect(draft.canSave == false)

        draft.name = String(repeating: "a", count: NewKeyDraft.nameLimit + 1)
        #expect(draft.canSave == false, "a name past the column's limit was allowed through")

        draft.name = String(repeating: "a", count: NewKeyDraft.nameLimit)
        #expect(draft.canSave)
    }

    @Test("saving writes the trimmed name, the chosen strength and its NDC")
    func whatReachesTheStore() async {
        let store = FakeAdder()
        let draft = NewKeyDraft(product: product("Nicorette", .lozenge, 2, 4), store: store)
        draft.name = "  Nicorette lozenge, mint  "
        draft.raise()

        let stored = await draft.save()

        #expect(stored != nil)
        #expect(store.added.count == 1)
        #expect(store.added.first?.key.label == "Nicorette lozenge, mint")
        #expect(store.added.first?.key.mg == 4)
        #expect(store.added.first?.key.form == .lozenge)
        #expect(store.added.first?.ndc == "Nicorette-4.0")
    }

    @Test("a save that fails keeps the screen and says why")
    func nothingTypedIsThrownAway() async {
        // Closing on a failure would discard everything typed to reach it, and
        // the one thing the user cannot do is get it back.
        let store = FakeAdder()
        store.fails = true
        let draft = NewKeyDraft(product: product("Nicorette", .gum, 2), store: store)

        let stored = await draft.save()

        #expect(stored == nil, "a failed write reported a key")
        guard case let .failed(message) = draft.status else {
            Issue.record("a failed save did not reach the failed state")
            return
        }
        #expect(message.contains("connection"))
        #expect(!message.contains("URLError"), "the error was shown raw")
        #expect(draft.canSave, "the screen refused to let them try again")
    }

    @Test("a build with no backend says so rather than failing quietly")
    func nothingToSaveInto() async {
        let draft = NewKeyDraft(product: product("Nicorette", .gum, 2), store: nil)

        #expect(await draft.save() == nil)
        #expect(draft.status == .failed(NewKeyDraft.noBackend))
    }
}
