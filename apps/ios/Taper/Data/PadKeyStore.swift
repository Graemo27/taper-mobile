import Foundation
import Supabase

/// A pad key as `pad_keys` holds it, once written.
///
/// The ledger is derived from the form rather than decoded, exactly as it is on
/// `PadKey`. The column is still written — the table's check constraint needs
/// both halves to compare — but reading it back would give the app a second
/// source for something it can already work out, and the constraint has
/// guaranteed the two agree since before the row existed.
struct StoredPadKey: Decodable, Equatable, Sendable {
    let id: Int
    let form: PadForm
    let label: String
    let mg: Double
    let position: Int
    /// The National Drug Code, for a key that came from the licensed lookup.
    /// Always nil for a seeded key: nothing in onboarding consults a catalogue.
    let ndc: String?

    var ledger: PadKey.Ledger { form.ledger }

    enum CodingKeys: String, CodingKey {
        case id, form, label, mg, position, ndc
    }
}

/// Putting keys on the pad, by the two routes that do it.
///
/// They are not variations of one write. `seed` is a bootstrap that refuses a
/// pad which already has keys; `add` is for a pad that has them and appends to
/// one ledger. A caller that picked the wrong one would either wipe out the
/// distinction or silently do nothing, so they are named apart rather than
/// overloaded.
protocol PadKeyWriting: Sendable {
    /// Writes the seeded keys, or returns what is already there.
    ///
    /// Seeding is a bootstrap, not a sync. Someone re-running onboarding has a
    /// pad they may since have renamed, reordered or added to, and replacing it
    /// with what the questions imply would throw that away — so a pad that
    /// already has keys is left exactly as it is.
    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey]

    /// Adds one key to the end of its own ledger, and returns it as stored.
    ///
    /// Separate from `seed` rather than a one-key call to it, because seeding
    /// deliberately refuses a pad that already has keys — which is every pad
    /// this is used on.
    ///
    /// `ndc` is the catalogue's own identifier for the exact product, carried
    /// so a key built from a search result can be traced back to the label it
    /// came from. Nil for a key somebody typed themselves, which is what the
    /// source ledger always is.
    func add(_ key: PadKey, ndc: String?) async throws -> StoredPadKey

    /// Takes one key off the pad.
    ///
    /// The row goes rather than being flagged. A key is a button, not a record
    /// of anything — every check-in it produced kept its own snapshot of the
    /// label and the milligrams, so removing the key cannot rewrite a single
    /// day that has already happened. That is what makes this safe to do
    /// outright where a check-in could not be.
    ///
    /// Positions are left alone. They only need to *order* a ledger, not
    /// enumerate it, so a gap where a key was is not a state to repair — and
    /// repairing it would mean rewriting every row after it for nothing.
    func remove(_ id: Int) async throws
}

/// Reading the pad already on file.
protocol PadKeyReading: Sendable {
    /// Every key this user has, in the order the pad draws them.
    ///
    /// Empty means *they have no keys*, never *we could not find out* — the
    /// same distinction `TaperPlanReading` draws, and for the same reason: one
    /// of those is a reason to seed and the other is a reason to say so.
    func currentKeys() async throws -> [StoredPadKey]
}

/// Both halves, for the caller that finishes onboarding and needs each.
typealias PadKeyStoring = PadKeyWriting & PadKeyReading

/// What the app writes through, once a backend is configured.
///
/// Named together because they are built together and must share one session:
/// the plan and the pad are written by a single tap, and two coordinators
/// racing to sign in on that tap is the thing `SessionCoordinator` exists to
/// prevent.
struct AppStores {
    let plans: any TaperPlanStoring
    /// The same object as `plans` in the app, named apart because the log asks
    /// it a question no other screen does.
    let planVersions: any PlanVersionReading
    let pad: any PadKeyStoring
    let checkIns: any CheckInStoring
    /// The licensed catalogue. Its own protocol because it is the only read in
    /// the app that goes through an Edge Function rather than a table.
    let nrt: any NRTSearching
    /// The daily check-in's one word per day.
    let ratings: any DayRatingStoring
}

/// The pad on the server: the whole of `pad_keys` for the signed-in anonymous
/// user, written and read.
///
/// Every position the pad draws is decided here rather than by a caller, because
/// each ledger numbers its own keys from zero and no screen sees both.
struct SupabasePadKeyStore: PadKeyWriting, PadKeyReading {
    let client: SupabaseClient
    let session: SessionCoordinator

    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey] {
        // Read first, and insert only into an empty pad. `pad_keys` has no
        // unique index to upsert against — a user may legitimately own two
        // lozenge keys at different strengths — so "already seeded" is a
        // question only the existing rows can answer.
        //
        // That makes this check-then-act, and the race is real: two submits
        // close enough together both see nothing and both insert, leaving a
        // doubled pad. It is bounded on purpose — nothing is lost, and the
        // duplicates are editable — and the caller holds a guard that keeps a
        // second submit from starting while the first is in flight. The
        // durable fix is a seeded marker or a unique index, and both are
        // migrations rather than client changes.
        let existing = try await currentKeys()
        guard existing.isEmpty else { return existing }
        guard !keys.isEmpty else { return [] }

        return try await session.authenticated { userID in
            try await client
                .from("pad_keys")
                .insert(keys.map { PadKeyRow(key: $0, userID: userID) })
                .select()
                .order("position")
                .execute()
                .value
        }
    }
}

extension SupabasePadKeyStore {
    func add(_ key: PadKey, ndc: String?) async throws -> StoredPadKey {
        // The position is read rather than sent by the caller: the pad draws
        // each ledger numbered from zero, and a screen that has not looked at
        // the other ledger cannot know where its own ends.
        //
        // Check-then-act, like `seed`, and the same race with the same bound:
        // two adds close enough together both read the same last position and
        // both take it. Postgres has no unique index on it — two keys may
        // legitimately share a position while a pad is being reordered — so
        // the cost is a pair drawn in an arbitrary order, not a failed write
        // or a lost key. The durable fix is a generated position, which is a
        // migration rather than a client change.
        let existing = try await currentKeys().filter { $0.form.ledger == key.ledger }
        let placed = PadKey(
            form: key.form, label: key.label, mg: key.mg,
            position: (existing.map(\.position).max() ?? -1) + 1
        )

        let rows: [StoredPadKey] = try await session.authenticated { userID in
            try await client
                .from("pad_keys")
                .insert([PadKeyRow(key: placed, userID: userID, ndc: ndc)])
                .select()
                .execute()
                .value
        }

        // `insert().select()` returns what Postgres actually wrote, so an empty
        // array means the write did not happen — reporting success on it would
        // put a key on the pad that no reload will bring back.
        guard let stored = rows.first else {
            throw PadKeyWriteFailure.keyWasNotWritten
        }
        return stored
    }

    func remove(_ id: Int) async throws {
        let removed: [StoredPadKey] = try await session.authenticated { userID in
            try await client
                .from("pad_keys")
                // Filtered by user as well as by id, for the reason the reads
                // give: a delete that is only safe because of a policy breaks
                // silently the day the policy is loosened, and this one cannot
                // be undone.
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: userID)
                .select()
                .execute()
                .value
        }

        // Nothing deleted is a failure, not a quiet success. RLS refusing the
        // delete reports it as zero rows, and telling somebody a key is gone
        // when the next read brings it back is worse than saying it did not
        // work.
        guard !removed.isEmpty else { throw PadKeyWriteFailure.keyWasNotRemoved }
    }

    func currentKeys() async throws -> [StoredPadKey] {
        try await session.authenticated { userID in
            // Filtered by user_id as well as trusting RLS, for the reason the
            // plan read gives: a query that is only safe because of a policy
            // breaks silently the day the policy is loosened.
            try await client
                .from("pad_keys")
                .select()
                .eq("user_id", value: userID)
                // The pad draws two groups, and `position` numbers each from
                // zero — so ordering by it alone interleaves them. Ledger
                // first, then position, which is the index this table carries.
                //
                // Then `id`, because position is not unique and Postgres makes
                // no promise about tied rows: two keys sharing a position would
                // otherwise come back in a different order from one read to the
                // next, and the pad would shuffle under someone who had touched
                // nothing. `id` breaks the tie by the order they were created,
                // which is the order the pad should draw them in anyway.
                .order("ledger")
                .order("position")
                .order("id")
                .execute()
                .value as [StoredPadKey]
        }
    }
}

/// What can go wrong writing a key, beyond what the client already throws.
enum PadKeyWriteFailure: Error, Equatable {
    /// The insert returned no row. RLS refusing a write reports it this way
    /// rather than as an error, so this is the difference between a key that
    /// exists and one the caller was told about.
    case keyWasNotWritten
    /// The delete matched no row. Someone else's key, or one already gone —
    /// either way the pad should not claim to have removed it.
    case keyWasNotRemoved
}

/// The row on the wire.
///
/// Written out by hand rather than derived from `PadKey`, the same way
/// `TaperPlanRow` is: the app's shape and the table's agreeing today is not a
/// reason to let one rename silently rewrite the other.
private struct PadKeyRow: Encodable {
    let userID: UUID
    let ledger: String
    let label: String
    let form: String
    let mg: Double
    let position: Int
    let ndc: String?

    init(key: PadKey, userID: UUID, ndc: String? = nil) {
        self.userID = userID
        // Both halves off the same value, so the pair the table checks cannot
        // be written in disagreement.
        ledger = key.ledger.rawValue
        form = key.form.rawValue
        label = key.label
        mg = key.mg
        position = key.position
        // Trimmed to nil rather than sent empty: the column's check refuses a
        // blank string, so an empty one would fail the whole insert where
        // "this key came from nowhere" is exactly what null already says.
        let trimmed = ndc?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ndc = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case ledger, label, form, mg, position, ndc
    }
}
