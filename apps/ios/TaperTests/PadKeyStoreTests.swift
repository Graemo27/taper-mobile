import Foundation
import Supabase
import Testing
@testable import Taper

/// Drives the pad store against a real Postgres with the real migrations
/// applied.
///
/// An extension of `LiveBackendTests` rather than a suite of its own, because
/// these tests sign in and out of the same persisted session the plan tests
/// use. A second top-level suite would run concurrently with that one and take
/// its identity out from under a request in flight.
///
/// The reason it is worth having at all is the seam the pad seed cannot reach
/// on its own: `PadForm` is the table's check constraint restated in Swift,
/// and a mapping that is wrong there builds cleanly, passes every unit test,
/// and fails as a rejected insert on somebody's phone.
extension LiveBackendTests {
    private func padStore() async -> SupabasePadKeyStore {
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        // A genuinely new anonymous person each time, for the reason the plan
        // store's helper gives: the simulator keeps a session across launches
        // while `supabase db reset` takes `auth.users` with it.
        try? await client.auth.signOut(scope: .local)
        return SupabasePadKeyStore(
            client: client,
            session: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        )
    }

    /// A run that named one of everything, so the seed exercises every source
    /// mapping in a single write.
    private func everySourceRun() -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        for source in NicotineSource.allCases { answers.toggle(source) }
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        answers.strengths[.nrt] = StrengthOption.nrt.first { $0.mg == 4 }
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true
        answers.toggle(TreatmentForm.patch)
        answers.toggle(TreatmentForm.lozenge)
        return answers
    }

    @Test("every key a real run produces is one the table accepts",
          .enabled(if: LocalBackend.isAvailable))
    func aWholeSeedIsAccepted() async throws {
        // The seam `PadKeyTests` cannot reach. Both ledgers, every source form
        // the app can emit, and the ledger/form pairing checked by Postgres
        // rather than by the enum that claims it.
        let answers = everySourceRun()
        let seeded = answers.padKeys(with: TaperPlanner.plan(for: answers.taperInput!).replacement)
        #expect(seeded.count == NicotineSource.allCases.count + 2, "the fixture must cover both ledgers")

        let stored = try await padStore().seed(seeded)

        #expect(stored.count == seeded.count)
        #expect(Set(stored.map(\.form)) == Set(seeded.map(\.form)))
        #expect(stored.allSatisfy { $0.ndc == nil }, "nothing in onboarding consults a catalogue")
    }

    @Test("a key comes back the way it went in",
          .enabled(if: LocalBackend.isAvailable))
    func aSeededKeyRoundTrips() async throws {
        // `mg` is `numeric(6, 2)` and every field here crosses a type boundary
        // a mock would agree with and a database would not.
        let key = PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)
        let store = await padStore()

        _ = try await store.seed([key])
        let found = try await store.currentKeys()

        #expect(found.count == 1)
        #expect(found.first?.form == .pouch)
        #expect(found.first?.label == "Pouches")
        #expect(found.first?.mg == 6)
        #expect(found.first?.position == 0)
        #expect(found.first?.ledger == .source, "the ledger is derived, and the row must agree")
    }

    @Test("seeding a pad that already has keys leaves it alone",
          .enabled(if: LocalBackend.isAvailable))
    func seedingIsABootstrapNotASync() async throws {
        // Re-running onboarding is the ordinary case — nothing yet records
        // that the run was completed — so this path runs again for somebody
        // who may since have renamed a key or added one. Writing the seed a
        // second time would double their pad.
        let store = await padStore()
        let first = try await store.seed([PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)])

        let second = try await store.seed([
            PadKey(form: .cigarette, label: "Cigarettes", mg: 1.5, position: 0),
            PadKey(form: .gum, label: "Gum", mg: 4, position: 0),
        ])

        #expect(second == first, "a second seed returned something other than the pad on file")
        #expect(try await store.currentKeys().count == 1, "the pad was written twice")
    }

    @Test("the pad reads back grouped by ledger, each numbered from zero",
          .enabled(if: LocalBackend.isAvailable))
    func theTwoGroupsDoNotInterleave() async throws {
        // Both ledgers number their positions from zero, so ordering by
        // position alone would shuffle a treatment key in among the sources.
        let store = await padStore()
        _ = try await store.seed([
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0),
            PadKey(form: .cigarette, label: "Cigarettes", mg: 1.5, position: 1),
            PadKey(form: .patch, label: "Patch", mg: 21, position: 0),
            PadKey(form: .lozenge, label: "Lozenge", mg: 4, position: 1),
        ])

        let ledgers = try await store.currentKeys().map(\.ledger)

        #expect(ledgers == [.source, .source, .treatment, .treatment])
    }

    @Test("a key added from the catalogue keeps the NDC it came from",
          .enabled(if: LocalBackend.isAvailable))
    func aCatalogueKeyCarriesItsLabelBack() async throws {
        // The seam nothing has ever crossed: `ndc` has a column and a check
        // constraint, and until now no write path filled it — onboarding never
        // consults a catalogue, so every key on the server has been null.
        let store = await padStore()

        let stored = try await store.add(
            PadKey(form: .lozenge, label: "Nicorette lozenge, mint", mg: 4, position: 0),
            ndc: "0135-0546"
        )

        #expect(stored.ndc == "0135-0546", "the key lost the label it was built from")
        #expect(stored.form == .lozenge)
        #expect(stored.mg == 4)
        #expect(try await store.currentKeys().count == 1)
    }

    @Test("an added key lands at the end of its own ledger, not the pad",
          .enabled(if: LocalBackend.isAvailable))
    func anAddedKeyCountsOnlyItsOwnLedger() async throws {
        // Both ledgers number from zero. Taking the highest position on the
        // whole pad would put a first treatment key at 2 behind two sources,
        // and the pad draws position order within a group.
        let store = await padStore()
        _ = try await store.seed([
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0),
            PadKey(form: .cigarette, label: "Cigarettes", mg: 1.5, position: 1),
        ])

        let first = try await store.add(
            PadKey(form: .gum, label: "Nicorette gum", mg: 2, position: 0), ndc: nil
        )
        let second = try await store.add(
            PadKey(form: .patch, label: "NicoDerm", mg: 21, position: 0), ndc: nil
        )

        #expect(first.position == 0, "the first treatment key was pushed behind the sources")
        #expect(second.position == 1, "the second key did not follow the first")
    }

    @Test("a key typed by hand carries no NDC rather than an empty one",
          .enabled(if: LocalBackend.isAvailable))
    func ablankNdcIsNullNotEmpty() async throws {
        // The column's check refuses a blank string, so sending one would fail
        // the whole insert — where null is already the way to say the key came
        // from nowhere.
        let store = await padStore()

        let stored = try await store.add(
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0), ndc: "   "
        )

        #expect(stored.ndc == nil, "whitespace was written as an NDC")
    }

    @Test("a tie cannot be made any more, which is what lets order be edited",
          .enabled(if: LocalBackend.isAvailable))
    func theTieIsRefusedRatherThanTolerated() async throws {
        // This test used to prove the opposite: that `position` was not unique
        // and the pad survived a tie by breaking it on id. The reasoning is
        // worth keeping because it is why the tie mattered at all.
        //
        // It takes a *non-HOT* update to see a tie go wrong. An ordinary
        // column update stays on its page and leaves every index entry alone,
        // so an index scan still yields the original order and the pad looks
        // stable whether or not anything breaks the tie. Rewriting an indexed
        // column reinserts the entry at the end of its equal-key group, and a
        // tied row jumps to the back of the pad — which is precisely what
        // reordering does. Tolerating ties and letting the user *set* the
        // order could not both be true, so the tie is now refused.
        let store = await padStore()

        await #expect(throws: (any Error).self) {
            _ = try await store.seed([
                PadKey(form: .gum, label: "First", mg: 2, position: 0),
                PadKey(form: .lozenge, label: "Second", mg: 4, position: 0),
            ])
        }

        // A seat is per ledger, so the same number in the other one is fine —
        // and is what every pad in the app actually looks like.
        let seeded = try await store.seed([
            PadKey(form: .gum, label: "Gum", mg: 2, position: 0),
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0),
        ])
        #expect(seeded.count == 2)

        for key in try await store.currentKeys() { try await store.remove(key.id) }
    }

    @Test("a key can be taken off the pad, and stays off",
          .enabled(if: LocalBackend.isAvailable))
    func aRemovedKeyIsGone() async throws {
        // The one write in this app that cannot be undone. Safe because a key
        // is a button rather than a record: every check-in it produced kept its
        // own snapshot of the label and the milligrams, so removing it cannot
        // rewrite a day that has already happened.
        let store = await padStore()
        let seeded = try await store.seed([
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0),
            PadKey(form: .vape, label: "Vape", mg: 2, position: 1),
        ])
        let going = try #require(seeded.first { $0.label == "Vape" })

        try await store.remove(going.id)

        let left = try await store.currentKeys()
        #expect(left.map(\.label) == ["Pouches"], "the wrong key went, or none did")
    }

    @Test("removing a key that is not there is a failure, not a quiet success",
          .enabled(if: LocalBackend.isAvailable))
    func nothingDeletedIsNotSuccess() async throws {
        // RLS refuses a delete by returning no rows rather than an error, so
        // somebody else's key and an already-gone key arrive the same way.
        // Reporting either as done would show a pad the next read contradicts.
        let store = await padStore()
        _ = try await store.seed([PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)])

        await #expect(throws: PadKeyWriteFailure.keyWasNotRemoved) {
            try await store.remove(999_999)
        }
        #expect(try await store.currentKeys().count == 1, "the pad lost a key anyway")
    }

    @Test("a delete that matches nobody's key is refused rather than reported done",
          .enabled(if: LocalBackend.isAvailable))
    func theDeleteIsScopedToItsOwner() async throws {
        // What the *client* does with a refusal. `remove` filters by user as
        // well as by id and RLS refuses it besides, so a stranger's delete
        // matches no row — and the store must call that a failure rather than
        // a success with nothing in it.
        let first = await padStore()
        let seeded = try await first.seed([
            PadKey(form: .pouch, label: "Mine", mg: 6, position: 0),
        ])
        let mine = try #require(seeded.first)

        // Whether the row survives is asserted in pgTAP, not here: `padStore()`
        // signs out to get a genuinely new anonymous person, and the client
        // persists one session — so reading as `first` again after this line
        // reads as a third user with an empty pad. Two users at once is a
        // thing the database can express and this suite cannot.
        let stranger = await padStore()
        await #expect(throws: PadKeyWriteFailure.keyWasNotRemoved) {
            try await stranger.remove(mine.id)
        }
    }

    @Test("a new anonymous session has an empty pad, rather than failing",
          .enabled(if: LocalBackend.isAvailable))
    func aNewUserHasNoKeys() async throws {
        // Having no pad is the ordinary state of everyone who has not finished
        // onboarding. Arriving as an error would make it indistinguishable
        // from a read that genuinely failed — and the seed decides what to do
        // next by asking exactly this question.
        #expect(try await padStore().currentKeys().isEmpty)
    }

    @Test("seeding nothing writes nothing",
          .enabled(if: LocalBackend.isAvailable))
    func anEmptySeedIsNotAnInsert() async throws {
        // PostgREST rejects an empty insert, so this has to be answered before
        // the request rather than by it.
        let store = await padStore()

        #expect(try await store.seed([]).isEmpty)
        #expect(try await store.currentKeys().isEmpty)
    }

    @MainActor
    @Test("one tap at the end of onboarding puts both the plan and the pad on the server",
          .enabled(if: LocalBackend.isAvailable))
    func finishingARunWritesEverything() async throws {
        // The whole path through the real stores: answers to a completed run,
        // one `submit`, and both tables written against the real schema. The
        // pieces are covered against fakes elsewhere; what only this can show
        // is that a run assembled by `completedRun(shown:)` produces rows both
        // tables actually accept, in one tap, in the order `submit` chose.
        //
        // It deliberately does *not* claim to prove the two stores share an
        // identity. A mutation splitting them onto separate clients and
        // separate coordinators still passes, because clients built against
        // one URL share the same session storage and resolve to the same
        // anonymous user. Sharing one `SessionCoordinator` in `liveStores()`
        // is about coalescing concurrent sign-ins into a single request, and
        // that remains an untested claim rather than one this test covers.
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try? await client.auth.signOut(scope: .local)
        let session = SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        let pad = SupabasePadKeyStore(client: client, session: session)
        let plans = SupabaseTaperPlanStore(client: client, session: session)

        // The sign-out above is `try?`, so a session can survive it — and a
        // surviving one already has a plan and a pad. Every assertion at the
        // bottom would then pass on rows this test did not write, including
        // the key count, because it is the same run that seeded them. Checked
        // rather than assumed: this is the shape where a green test and a
        // broken write are compatible states.
        #expect(try await plans.currentPlan() == nil, "a previous session survived the sign-out")
        #expect(try await pad.currentKeys().isEmpty, "a previous session survived the sign-out")

        let answers = everySourceRun()
        let run = answers.completedRun(shown: answers.planPreview!)!
        let record = PlanRecord(store: plans, pad: pad)

        await record.submit(run)

        // The submit's own verdict, not only what is on the server. Without it
        // a write that failed and left the earlier rows in place reads exactly
        // like a write that succeeded.
        #expect(record.status.isPresent, "the run did not finish")
        #expect(try await plans.currentPlan() != nil, "the plan is not readable as this user")
        #expect(try await pad.currentKeys().count == run.padKeys.count,
                "the pad is not readable as this user")
    }

    @Test("the pad suite leaves no session behind",
          .enabled(if: LocalBackend.isAvailable))
    func padTestsSignOutWhenDone() async throws {
        // Teardown as a test, because `.serialized` runs in source order and
        // `deinit` cannot await. These tests and the UI suite share an app
        // container: a session left signed in is the identity the next
        // launched app picks up.
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try await client.auth.signOut(scope: .local)

        await #expect(throws: (any Error).self) {
            try await client.auth.session
        }
    }

    @Test("a key is seated by the database, at the end of its own ledger",
          .enabled(if: LocalBackend.isAvailable))
    func theSeatIsNotTheClientsToChoose() async throws {
        // #126's race, closed where it had to be. The client used to read the
        // last position and add one — check-then-act, so two adds close
        // enough together both took the same seat. It sends no position now.
        let store = await padStore()
        _ = try await store.seed([
            PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0),
            PadKey(form: .lozenge, label: "Lozenge", mg: 4, position: 0),
        ])

        let added = try await store.add(
            PadKey(form: .vape, label: "Vape", mg: 2, position: 99), ndc: String?.none
        )

        #expect(added.position == 1, "the client's own number reached the row")

        let pad = Pad(keys: try await store.currentKeys())
        #expect(pad.sources.map(\.label) == ["Pouches", "Vape"])
        #expect(pad.treatment.map(\.position) == [0],
                "the ledgers were seated against each other")

        for key in try await store.currentKeys() { try await store.remove(key.id) }
    }

    @Test("two adds at once take different seats",
          .enabled(if: LocalBackend.isAvailable))
    func theRaceIsClosedRatherThanNarrowed() async throws {
        // The failure this migration exists for. Run concurrently, the old
        // read-then-add gave both keys the same position; the trigger's
        // advisory lock makes them take turns. Ten so the window is not
        // squinted at.
        let store = await padStore()
        _ = try await store.seed([PadKey(form: .pouch, label: "Pouches", mg: 6, position: 0)])

        await withTaskGroup(of: Void.self) { group in
            for index in 1...10 {
                group.addTask {
                    _ = try? await store.add(
                        PadKey(form: .vape, label: "Vape \(index)", mg: 2, position: 0), ndc: String?.none
                    )
                }
            }
        }

        let seats = Pad(keys: try await store.currentKeys()).sources.map(\.position)
        #expect(seats.count == 11)
        #expect(Set(seats).count == seats.count, "two keys claimed one seat")
        #expect(seats.sorted() == Array(0...10), "the ledger has gaps or repeats")

        for key in try await store.currentKeys() { try await store.remove(key.id) }
    }
}
