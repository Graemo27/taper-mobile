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

/// Covers the source key somebody adds by hand: what it may be, what it is
/// measured in, and that nothing about it ever consults a catalogue.
@MainActor
struct NewSourceDraftTests {
    @Test("the pad can gain a source, which is what keeps the cap honest")
    func whatReachesTheStore() async {
        // A source somebody cannot log is a cap that silently lies: every use
        // goes unrecorded, the day reads under the ceiling, and the number the
        // whole app is built on stops meaning anything.
        let store = FakeAdder()
        let draft = NewSourceDraft(source: .pouches, store: store)

        let stored = await draft.save()

        #expect(stored != nil)
        #expect(store.added.count == 1)
        #expect(store.added.first?.key.form == .pouch)
        #expect(store.added.first?.key.label == "Pouches")
        #expect(store.added.first?.key.ledger == .source, "a source was filed as a treatment")
    }

    @Test("nothing added here ever carries an NDC")
    func aHandTypedKeyCitesNoLabel() async {
        // The NDC means "this came from the licensed catalogue". Every source
        // is the user's own word, and a key claiming a label it was not built
        // from is a lie the rest of the app would believe.
        let store = FakeAdder()

        for source in NewSourceDraft.sources {
            let draft = NewSourceDraft(source: source, store: store)
            _ = await draft.save()
        }

        #expect(store.added.count == NewSourceDraft.sources.count)
        #expect(store.added.allSatisfy { $0.ndc == nil }, "a hand-typed key cited a drug label")
    }

    @Test("every source offered files on the quitting ledger, and NRT is not offered")
    func onlyThingsBeingQuitAreHere() {
        // Gum and lozenges are treatments. Offering them here would file a
        // treatment on the wrong ledger, which the table's own check rejects —
        // and would put a hand-typed entry where a licensed lookup belongs.
        for source in NewSourceDraft.sources {
            #expect(source.padForm.ledger == .source, "\(source) is not something being quit")
        }
        #expect(!NewSourceDraft.sources.contains(.nrt), "NRT was offered as a thing to quit")
    }

    @Test("each source is measured on its own ladder")
    func aPouchAndAPuffAreNotTheSameSizeOfThing() {
        // A single step would either make the pouch take twenty presses or put
        // the vape at a figure nobody's device delivers.
        let pouch = NewSourceDraft.strengths(for: .pouches)
        let vape = NewSourceDraft.strengths(for: .vape)

        #expect(pouch.first == 2)
        #expect(vape.first == 0.05)
        #expect(vape.max()! < pouch.min()!, "the vape ladder reached pouch strengths")

        for source in NewSourceDraft.sources {
            let rungs = NewSourceDraft.strengths(for: source)
            #expect(rungs == rungs.sorted(), "\(source)'s strengths are not low to high")
            #expect(rungs.allSatisfy { $0 > 0 }, "\(source) offers a strength the table refuses")
        }
    }

    @Test("the pouch ladder is the one onboarding already offers")
    func twoPathsDoNotQuoteDifferentTables() {
        // A key added here and a key seeded by onboarding must be numbers from
        // the same table, or the pad shows two answers to one question.
        let asked = Set(StrengthOption.pouch.compactMap(\.mg))
        let offered = Set(NewSourceDraft.strengths(for: .pouches))

        #expect(asked.isSubset(of: offered), "onboarding can produce a pouch strength this refuses")
    }

    @Test("the ladder opens on the figure onboarding would have used")
    func thePathsAgreeOnWhereToStart() {
        // Opening at whichever end the list begins would put a cigarette at
        // 0.5 mg when the app's own estimate for one is 1.5.
        for source in NewSourceDraft.sources {
            let draft = NewSourceDraft(source: source, store: nil)
            guard let estimate = source.estimatedMgPerUnit else { continue }
            #expect(draft.mg == estimate, "\(source) opened somewhere other than its own estimate")
        }
        #expect(NewSourceDraft(source: .pouches, store: nil).mg == 6, "the board opens on 6 mg")
    }

    @Test("changing the source moves the ladder under it")
    func aVapeDoesNotInheritAPouchStrength() {
        // Keeping the rung would carry 6 mg across to a vape, which is forty
        // times what a puff delivers.
        let draft = NewSourceDraft(source: .pouches, store: nil)
        #expect(draft.mg == 6)

        draft.source = .vape

        #expect(draft.mg == 0.15, "the vape kept a pouch's strength")
        #expect(draft.label == "Vape")
    }

    @Test("the stepper stops at both ends of its ladder")
    func itCannotStepOffTheEdge() {
        let draft = NewSourceDraft(source: .cigarettes, store: nil)
        let rungs = NewSourceDraft.strengths(for: .cigarettes)

        while draft.canLower { draft.lower() }
        #expect(draft.mg == rungs.first)
        draft.lower()
        #expect(draft.mg == rungs.first, "it stepped below the weakest rung")

        while draft.canRaise { draft.raise() }
        #expect(draft.mg == rungs.last)
        draft.raise()
        #expect(draft.mg == rungs.last, "it stepped past the strongest rung")
    }

    @Test("a save that fails keeps the screen and says why")
    func nothingAnsweredIsThrownAway() async {
        let store = FakeAdder()
        store.fails = true
        let draft = NewSourceDraft(source: .dip, store: store)

        #expect(await draft.save() == nil, "a failed write reported a key")
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
        let draft = NewSourceDraft(source: .pouches, store: nil)

        #expect(await draft.save() == nil)
        #expect(draft.status == .failed(NewSourceDraft.noBackend))
    }
}
