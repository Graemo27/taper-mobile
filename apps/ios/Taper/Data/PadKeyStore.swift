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

/// Writing the pad.
protocol PadKeyWriting: Sendable {
    /// Writes the seeded keys, or returns what is already there.
    ///
    /// Seeding is a bootstrap, not a sync. Someone re-running onboarding has a
    /// pad they may since have renamed, reordered or added to, and replacing it
    /// with what the questions imply would throw that away — so a pad that
    /// already has keys is left exactly as it is.
    func seed(_ keys: [PadKey]) async throws -> [StoredPadKey]
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

/// The real one.
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
                .order("ledger")
                .order("position")
                .execute()
                .value as [StoredPadKey]
        }
    }
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

    init(key: PadKey, userID: UUID) {
        self.userID = userID
        // Both halves off the same value, so the pair the table checks cannot
        // be written in disagreement.
        ledger = key.ledger.rawValue
        form = key.form.rawValue
        label = key.label
        mg = key.mg
        position = key.position
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case ledger, label, form, mg, position
    }
}
