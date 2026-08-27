import Foundation
import Supabase

/// An entry about to be written.
///
/// Carries the key it came from rather than a copy of its fields, so the
/// snapshot is taken in one place — the row builder — instead of at every call
/// site that might take a slightly different copy.
struct CheckInDraft: Equatable, Sendable {
    /// The key that was tapped, or nil when nothing was.
    ///
    /// Nil is what an urge is: the craving screen records getting through one,
    /// and there was no key on the pad to press. Provenance only either way —
    /// every other field here is the snapshot the log actually renders.
    let padKeyID: Int?
    let ledger: PadKey.Ledger
    let label: String
    let form: PadForm
    let mg: Double
    let quantity: Int
    /// The day it belongs to, as the user reckons days.
    let day: Date

    init(pending: PendingEntry, day: Date) {
        padKeyID = pending.key.id
        ledger = pending.key.ledger
        label = pending.key.label
        form = pending.key.form
        mg = pending.key.mg
        quantity = pending.quantity
        self.day = day
    }

    private init(
        padKeyID: Int?, ledger: PadKey.Ledger, label: String,
        form: PadForm, mg: Double, quantity: Int, day: Date
    ) {
        self.padKeyID = padKeyID
        self.ledger = ledger
        self.label = label
        self.form = form
        self.mg = mg
        self.quantity = quantity
        self.day = day
    }

    /// A craving somebody got through, recorded as costing nothing.
    ///
    /// Zero milligrams and no key, which is the shape `check_ins` now requires
    /// of anything at zero — a nought-milligram *product* is still refused.
    ///
    /// Filed on the treatment ledger because that is where the board draws it,
    /// and because the other ledger counts against the day's ceiling: an urge
    /// that passed must not read as something used. `.other` for the form
    /// rather than a new case, since `form` is a snapshot the log prints and
    /// `label` is what carries the meaning.
    /// A licensed product logged straight from the catalogue, no key pressed.
    ///
    /// Keyless but not costless — the schema's zero-only-when-keyless rule is
    /// untouched because `mg > 0` here. Treatment ledger always: everything
    /// the catalogue can return is licensed NRT, which is the same rule that
    /// keeps a source out of the search results in the first place.
    /// Nil for a strength that is not a dose. A keyless zero-milligram
    /// treatment row is the exact shape `isUrge` reads back as a craving
    /// outlasted, so refusing it here keeps a catalogue gap from ever being
    /// filed as somebody's willpower.
    static func product(
        brand: String, form: PadForm, mg: Double, quantity: Int, on day: Date
    ) -> CheckInDraft? {
        guard mg > 0 else { return nil }
        return CheckInDraft(
            padKeyID: nil, ledger: .treatment, label: brand,
            form: form, mg: mg,
            quantity: min(max(quantity, PendingEntry.quantityRange.lowerBound),
                          PendingEntry.quantityRange.upperBound),
            day: day
        )
    }

    static func urgePassed(on day: Date) -> CheckInDraft {
        CheckInDraft(
            padKeyID: nil, ledger: .treatment, label: Self.urgeLabel,
            form: .other, mg: 0, quantity: 1, day: day
        )
    }

    /// What an urge is called wherever it is read back.
    ///
    /// One constant rather than a literal in each place, because the log, the
    /// day's count and the craving screen all have to agree about which rows
    /// are urges — and they have only the label to go on.
    static let urgeLabel = "Urge passed"

    /// Whether this row is an urge rather than something taken.
    var isUrge: Bool { padKeyID == nil && mg == 0 }
}

/// Writing an entry.
protocol CheckInWriting: Sendable {
    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn
}

/// Reading days back.
protocol CheckInReading: Sendable {
    /// Everything logged across a span of days, inclusive of both ends, in the
    /// order it was logged.
    ///
    /// A range rather than a day because the log draws a run of them and one
    /// request is cheaper than seven — and because a per-day loop would report
    /// a week as seven independent successes and failures, which is not how
    /// anybody reads a week.
    ///
    /// An empty span is a value, never an error. Most days start that way, and
    /// the days before somebody joined are legitimately empty.
    func entries(from first: Date, to last: Date) async throws -> [StoredCheckIn]
}

extension CheckInReading {
    /// One day, which is the span from it to itself.
    ///
    /// Kept because most callers want exactly one and `from: day, to: day`
    /// reads like a mistake at the call site.
    func entries(on day: Date) async throws -> [StoredCheckIn] {
        try await entries(from: day, to: day)
    }
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

/// Reads, writes and removes a day's check-ins through Supabase, as the
/// signed-in anonymous user.
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

    func entries(from first: Date, to last: Date) async throws -> [StoredCheckIn] {
        // Ordered by the caller's own dates rather than trusted. A span handed
        // over backwards would match nothing and read as an empty week, which
        // is a wrong answer that looks like a right one.
        let (start, end) = first <= last ? (first, last) : (last, first)
        let from = PlanDay.wireFormat(start, timeZone: timeZone)
        let to = PlanDay.wireFormat(end, timeZone: timeZone)
        return try await session.authenticated { userID in
            // Filtered by user_id as well as trusting RLS, for the reason the
            // other reads give: a query that is only safe because of a policy
            // breaks silently the day the policy is loosened.
            try await client
                .from("check_ins")
                .select()
                .eq("user_id", value: userID)
                .gte("logged_on", value: from)
                .lte("logged_on", value: to)
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
    /// Optional, because an urge tapped no key. PostgREST omits nothing — a nil
    /// here is sent as JSON null, which is what the column wants.
    let padKeyID: Int?
    let loggedOn: String
    let ledger: String
    let label: String
    let form: String
    let mg: Double
    let quantity: Int

    init(draft: CheckInDraft, userID: UUID, timeZone: TimeZone) {
        self.userID = userID
        padKeyID = draft.padKeyID
        // The same function the plan's dates go through. A second way of
        // turning an instant into a day is a second chance to store the wrong
        // one — and a check-in at 9pm in California landing on tomorrow is a
        // day whose total is quietly wrong at both ends.
        loggedOn = PlanDay.wireFormat(draft.day, timeZone: timeZone)
        ledger = draft.ledger.rawValue
        label = draft.label
        form = draft.form.rawValue
        mg = draft.mg
        quantity = draft.quantity
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case padKeyID = "pad_key_id"
        case loggedOn = "logged_on"
        case ledger, label, form, mg, quantity
    }
}
