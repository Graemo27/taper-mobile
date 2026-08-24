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

    @Test("a key that leaves a tie and comes back does not lose its place",
          .enabled(if: LocalBackend.isAvailable))
    func tiedPositionsDrawInTheOrderTheyWereMade() async throws {
        // `position` is not unique — two `add` calls close enough together both
        // read the same last one — and Postgres promises nothing about the
        // order of tied rows.
        //
        // It takes a *non-HOT* update to see it, which is why this moves
        // `position` rather than something cheaper. An ordinary column update
        // stays on its page and leaves every index entry alone, so an index
        // scan still yields the original order and the pad looks stable whether
        // or not anything breaks the tie. Rewriting an indexed column reinserts
        // the entry at the end of its equal-key group, and the row jumps to the
        // back of the pad.
        //
        // That is not a hypothetical write: it is precisely what reordering the
        // pad does, which is the feature this ordering has to survive.
        let client = AppSupabase.make(url: LocalBackend.url!, publishableKey: LocalBackend.key!)
        try? await client.auth.signOut(scope: .local)
        let store = SupabasePadKeyStore(
            client: client,
            session: SessionCoordinator(auth: SupabaseAnonymousAuth(client: client))
        )
        let seeded = try await store.seed([
            PadKey(form: .gum, label: "First", mg: 2, position: 0),
            PadKey(form: .lozenge, label: "Second", mg: 4, position: 0),
            PadKey(form: .patch, label: "Third", mg: 21, position: 0),
        ])
        #expect(Set(seeded.map(\.position)) == [0], "the fixture must tie every position")

        let before = try await store.currentKeys()
        #expect(before.count == 3, "the fixture did not land")
        let moved = try #require(before.first)

        for position in [1, 0] {
            let rewritten: [StoredPadKey] = try await client.from("pad_keys")
                .update(["position": position])
                .eq("id", value: moved.id)
                .select()
                .execute()
                .value
            #expect(rewritten.map(\.id) == [moved.id],
                    "the update did not rewrite exactly the key it was given")
        }

        #expect(try await store.currentKeys().map(\.id) == before.map(\.id),
                "a key that left the tie came back at the end of the pad")
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
}
