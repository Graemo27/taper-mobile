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
        var holds = false
    }

    /// Keeps a write suspended so a second one can be attempted while the
    /// first is still in flight.
    var holds: Bool {
        get { lock.withLock { state.holds } }
        set { lock.withLock { state.holds = newValue } }
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
        while holds { await Task.yield() }
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

    @Test("a thing that is not being quit cannot be made into a source key")
    func nrtHasNoWayIn() async {
        // `.nrt` maps to `.other`, which *is* a source form — so nothing
        // downstream refuses it. Excluding it from the offered list was a
        // claim in a docstring; this makes it a property of the type.
        let store = FakeAdder()
        let draft = NewSourceDraft(source: .nrt, store: store)
        #expect(draft.source == .pouches, "a draft was built for something not being quit")

        draft.select(.nrt)
        #expect(draft.source == .pouches, "NRT was selected through the source path")

        _ = await draft.save()
        #expect(store.added.first?.key.label == "Pouches")
        #expect(store.added.allSatisfy { $0.key.label != NicotineSource.nrt.label },
                "licensed gum was filed on the quitting ledger")
    }

    @Test("editing during a save does not let it be submitted twice")
    func oneSubmitWritesOneKey() async {
        // `canSave` is the only thing stopping a second submit, and it reads
        // `status`. Resetting that on every edit re-armed the button, so
        // changing the source mid-flight wrote the key twice.
        let store = FakeAdder()
        store.holds = true
        let draft = NewSourceDraft(source: .pouches, store: store)

        async let first = draft.save()
        // Bounded. An unbounded wait does not fail when the write never
        // starts, it hangs — and the suite then reports a timeout somewhere
        // else rather than the assertion that would have named the fault.
        // This test already hung once, on its own broken-code run.
        let deadline = Date().addingTimeInterval(3)
        while store.added.isEmpty, Date() < deadline { await Task.yield() }
        #expect(store.added.count == 1, "the first write never started")

        draft.select(.vape)
        draft.raise()
        #expect(draft.canSave == false, "a save in flight left the button armed")

        // Attempted without waiting on it. Awaiting here would hang rather than
        // fail when the guard is missing — the second save reaches the held
        // write and sits there, and a test that hangs teaches nothing.
        let second = Task { await draft.save() }
        store.holds = false
        _ = await first
        _ = await second.value

        #expect(store.added.count == 1, "one submit wrote \(store.added.count) keys")
    }

    @Test("changing the source moves the ladder under it")
    func aVapeDoesNotInheritAPouchStrength() {
        // Keeping the rung would carry 6 mg across to a vape, which is forty
        // times what a puff delivers.
        let draft = NewSourceDraft(source: .pouches, store: nil)
        #expect(draft.mg == 6)

        draft.select(.vape)

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

/// Covers the copy on the screen for adding what somebody is quitting.
@MainActor
struct NewSourceKeyViewTests {
    @Test("the screen says there is no catalogue, before anybody looks for one")
    func theAbsentSearchIsExplained() {
        // The treatment screen offers a search and this one cannot. Somebody
        // who has just used the other will notice, and saying why turns an
        // apparent gap into a stated boundary.
        #expect(NewSourceKeyView.subtitle.contains("not a brand"))
        #expect(NewSourceKeyView.subtitle.contains("doesn't keep a catalogue"))
    }

    @Test("the strength note gives permission to be approximate")
    func precisionIsAPromiseTheDataCannotKeep() {
        // Measured extraction from commercial pouches ran 38%, 24% and 52%, so
        // the figure on the tin is not what reaches anybody. Logging the same
        // way each day is what makes the trend true.
        #expect(NewSourceKeyView.strengthNote.contains("rough number is fine"))
        #expect(NewSourceKeyView.strengthNote.contains("same way every time"))
    }

    @Test("a chip names one of a thing, not a plural")
    func theChipsReadAsSingularForms() {
        // The key says "Pouches" because it stands for all of them; a chip is
        // picking what kind one is.
        let chips = NewSourceDraft.sources.map(NewSourceKeyView.chipLabel(for:))

        #expect(chips == ["Pouch", "Vape", "Cigarette", "Dip", "Other"])
        #expect(NewSourceDraft(source: .pouches, store: nil).label == "Pouches",
                "the key lost the label the pad shows")
    }
}

/// Covers what an empty pad says about itself.
@MainActor
struct EmptyPadNoteTests {
    @Test("an empty pad does not claim the way out of it is unbuilt")
    func theNoteDoesNotOutliveItsOwnTruth() {
        // It used to end "adding them by hand isn't built yet", and went on
        // saying so on the one screen where somebody needed to hear the
        // opposite. This is the assertion that would have caught it: the copy
        // is checked against the thing it describes, not read once and trusted.
        let note = PadView.emptyNote

        #expect(!note.contains("isn't built"), "the empty pad still refuses a screen that exists")
        #expect(!note.contains("not built"))
        #expect(note.contains("quitting"), "it did not name the ledger it can now fill")
        #expect(note.contains("treating"), "it did not name the other one")
    }
}
