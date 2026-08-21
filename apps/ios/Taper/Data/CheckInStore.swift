import Foundation
import Supabase

/// An entry about to be written.
///
/// Carries the key it came from rather than a copy of its fields, so the
/// snapshot is taken in one place — the row builder — instead of at every call
/// site that might take a slightly different copy.
struct CheckInDraft: Equatable, Sendable {
    let key: StoredPadKey
    let quantity: Int
    /// The day it belongs to, as the user reckons days.
    let day: Date

    init(pending: PendingEntry, day: Date) {
        key = pending.key
        quantity = pending.quantity
        self.day = day
    }
}

/// Writing an entry.
protocol CheckInWriting: Sendable {
    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn
}

/// Reading a day back.
protocol CheckInReading: Sendable {
    /// Everything logged on that day, in the order it was logged.
    ///
    /// An empty day is a value, never an error — most days start that way, and
    /// the tally asks this question before anything is on screen.
    func entries(on day: Date) async throws -> [StoredCheckIn]
}

/// Taking an entry back.
///
/// Separate from writing because it is a different permission and a different
/// intention. `check_ins` grants delete to its owner deliberately — a log
/// nobody can correct is one people stop trusting, and a mis-tap that
/// permanently distorts the cap is worse than no record at all.
protocol CheckInRemoving: Sendable {
    /// Removes one entry, by id.
    ///
    /// By id and never by content: two 3 mg pouches an hour apart are an
    /// ordinary afternoon, and a delete matched on what an entry *says* would
    /// take the wrong one about half the time.
    func remove(_ id: Int) async throws
}

/// All three, for the screen that logs, totals and corrects.
typealias CheckInStoring = CheckInWriting & CheckInReading & CheckInRemoving

/// The real one.
struct SupabaseCheckInStore: CheckInWriting, CheckInReading, CheckInRemoving {
    let client: SupabaseClient
    let session: SessionCoordinator
    /// The zone the user's day is reckoned in, fixed in tests for the reason
    /// `SupabaseTaperPlanStore` gives: on a UTC runner no local time disagrees
    /// with UTC, so a serialization regression round-trips perfectly.
    var timeZone: TimeZone = .current

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        try await session.authenticated { userID in
            try await client
                .from("check_ins")
                .insert(CheckInRow(draft: draft, userID: userID, timeZone: timeZone))
                .select()
                .single()
                .execute()
                .value
        }
    }
}

extension SupabaseCheckInStore {
    func remove(_ id: Int) async throws {
        try await session.authenticated { userID in
            // Both predicates, though either alone would do: RLS scopes the
            // delete to its owner, and the id is unique. Written out because a
            // delete is the one statement where a missing filter is not a bug
            // that shows up as wrong data — it shows up as no data.
            _ = try await client
                .from("check_ins")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: userID)
                .execute()
                .status
        }
    }

    func entries(on day: Date) async throws -> [StoredCheckIn] {
        let wire = PlanDay.wireFormat(day, timeZone: timeZone)
        return try await session.authenticated { userID in
            // Filtered by user_id as well as trusting RLS, for the reason the
            // other reads give: a query that is only safe because of a policy
            // breaks silently the day the policy is loosened.
            try await client
                .from("check_ins")
                .select()
                .eq("user_id", value: userID)
                .eq("logged_on", value: wire)
                // By id, which is insertion order. `created_at` would be the
                // obvious choice and is worse: two taps inside the same clock
                // tick would be free to swap, and the day's list is something
                // people scan for the thing they just added.
                .order("id")
                .execute()
                .value as [StoredCheckIn]
        }
    }
}

/// The row on the wire.
///
/// A snapshot, not a reference. `label`, `form`, `mg` and `ledger` are copied
/// off the key at the moment of the tap and never read back through it —
/// correcting a key's strength must not silently rewrite what somebody
/// recorded last Tuesday, and `pad_key_id` is provenance only.
private struct CheckInRow: Encodable {
    let userID: UUID
    let padKeyID: Int
    let loggedOn: String
    let ledger: String
    let label: String
    let form: String
    let mg: Double
    let quantity: Int

    init(draft: CheckInDraft, userID: UUID, timeZone: TimeZone) {
        self.userID = userID
        padKeyID = draft.key.id
        // The same function the plan's dates go through. A second way of
        // turning an instant into a day is a second chance to store the wrong
        // one — and a check-in at 9pm in California landing on tomorrow is a
        // day whose total is quietly wrong at both ends.
        loggedOn = PlanDay.wireFormat(draft.day, timeZone: timeZone)
        ledger = draft.key.ledger.rawValue
        label = draft.key.label
        form = draft.key.form.rawValue
        mg = draft.key.mg
        quantity = draft.quantity
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case padKeyID = "pad_key_id"
        case loggedOn = "logged_on"
        case ledger, label, form, mg, quantity
    }
}
