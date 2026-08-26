import Foundation

/// One entry as `check_ins` holds it, once written.
///
/// The ledger is **read from the row**, not derived from the form — the
/// opposite of `StoredPadKey`. `check_ins` is a snapshot by design ("the log
/// must render without a join") and, unlike `pad_keys`, it puts no constraint
/// on the form/ledger pair. Deriving here would let today's rules rewrite what
/// somebody recorded last Tuesday, which is the one thing an audit trail must
/// never do.
struct StoredCheckIn: Decodable, Equatable, Sendable {
    let id: Int
    /// The key that was tapped, or nil when none was.
    ///
    /// Decoded so the day can tell an urge from a dose. Nil alone does not mean
    /// urge — `on delete set null` empties this for any row whose key was later
    /// removed from the pad — which is why `isUrge` asks for zero milligrams as
    /// well.
    let padKeyID: Int?
    let ledger: PadKey.Ledger
    let label: String
    /// What it was, as far as this build can tell.
    ///
    /// Decoded leniently: an unrecognised value becomes `.other` rather than
    /// failing. The read decodes an *array*, so a closed enum meant one row
    /// carrying a word this build had never heard of made the whole day — and
    /// the whole history — unreadable. A newer client, or a backend that
    /// learned a form first, is enough to cause that.
    ///
    /// `label` is the snapshot and carries the meaning regardless, so the cost
    /// of not recognising a form is a row drawn plainly, not a row lost.
    let form: PadForm
    let mg: Double
    let quantity: Int
    /// The day this belongs to, as the reader's own calendar had it.
    ///
    /// The column a day is *counted* by, and not the same question as
    /// `createdAt`. A check-in at 11:58pm in California is that day's whatever
    /// UTC thinks, so grouping a week by the server's clock would file the last
    /// tap of a night under tomorrow — which is the bug `logged_on` exists to
    /// prevent, arriving one layer up.
    let loggedOn: String

    /// When the row was written, off the server's clock.
    ///
    /// Not the same question as `logged_on`, which is the reader's own date and
    /// is what a day is counted by. This is the moment, and it is only ever
    /// shown — a check-in made at 11:58pm in California belongs to that day
    /// whatever UTC thinks, which is why the two columns exist separately.
    let createdAt: Date

    /// Written out because the lenient `init(from:)` below suppresses the
    /// memberwise one the previews and tests build rows with.
    init(
        id: Int,
        ledger: PadKey.Ledger,
        label: String,
        form: PadForm,
        mg: Double,
        quantity: Int,
        loggedOn: String,
        createdAt: Date,
        /// Defaulted, because every caller that predates the craving screen is
        /// describing a row that came from a key being pressed.
        padKeyID: Int? = 0
    ) {
        self.id = id
        self.padKeyID = padKeyID
        self.ledger = ledger
        self.label = label
        self.form = form
        self.mg = mg
        self.quantity = quantity
        self.loggedOn = loggedOn
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(Int.self, forKey: .id)
        padKeyID = try row.decodeIfPresent(Int.self, forKey: .padKeyID)
        ledger = try row.decode(PadKey.Ledger.self, forKey: .ledger)
        label = try row.decode(String.self, forKey: .label)
        // The one lenient field. Everything else is this build's own vocabulary
        // or a plain value; `form` is the only column a future write could put
        // an unfamiliar word in.
        form = PadForm(rawValue: try row.decode(String.self, forKey: .form)) ?? .other
        mg = try row.decode(Double.self, forKey: .mg)
        quantity = try row.decode(Int.self, forKey: .quantity)
        loggedOn = try row.decode(String.self, forKey: .loggedOn)
        createdAt = try row.decode(Date.self, forKey: .createdAt)
    }

    /// What this entry contributes: the strength, however many times.
    var totalMg: Double { mg * Double(quantity) }

    /// Whether this is a craving somebody got through rather than a dose.
    ///
    /// Both halves are needed. A row whose key was deleted also has no
    /// `pad_key_id`, and a zero on its own is a shape the column still permits
    /// for a product — so an urge is the row that has neither a key nor an
    /// amount.
    var isUrge: Bool { padKeyID == nil && mg == 0 }

    /// The moment, as a clock reads it: "12:40 pm", or "12:40" where that is
    /// how people tell the time.
    ///
    /// Lowercased because the board sets it that way and because a row is a
    /// list of small facts, not a heading. Locale-aware rather than forced to
    /// twelve hours — the separator lesson from #110 applies here too, and a
    /// 24-hour reader should get a 24-hour clock.
    var timeText: String {
        createdAt.formatted(date: .omitted, time: .shortened).lowercased()
    }

    /// "Pouch · 12:40 pm" — the category it files under, and when.
    var detailText: String { "\(form.label) · \(timeText)" }

    enum CodingKeys: String, CodingKey {
        case id, ledger, label, form, mg, quantity
        case padKeyID = "pad_key_id"
        case loggedOn = "logged_on"
        case createdAt = "created_at"
    }
}

/// A key chosen but not yet logged.
///
/// Quantity is clamped to the range the column accepts. A number the database
/// would reject is one the screen should never have been able to build, and
/// clamping here means the failure is a bounded count rather than a rejected
/// insert after the tap.
struct PendingEntry: Equatable, Sendable {
    let key: StoredPadKey
    let quantity: Int

    /// The column is `smallint ... check (quantity between 1 and 20)`.
    static let quantityRange = 1...20

    init(key: StoredPadKey, quantity: Int = 1) {
        self.key = key
        self.quantity = min(max(quantity, Self.quantityRange.lowerBound), Self.quantityRange.upperBound)
    }

    var totalMg: Double { key.mg * Double(quantity) }

    /// "Pouch × 1", as the board reads it back above the figure.
    var recap: String { "\(key.label) × \(quantity)" }
}

/// Today: what has been logged, what is about to be, and the ceiling it is all
/// measured against.
///
/// **Only the source ledger counts.** Treatment is logged and never added in —
/// a patch is what carries somebody under the cap, and counting it against them
/// would make using the treatment look like failing. The board says as much on
/// the pad itself, where only one section is labelled "counts toward the
/// ceiling".
///
/// Nothing here refuses anything. Going over is reported, never blocked or
/// clamped: *the app is a witness, not a referee.* A tracker that argues with
/// the user gets closed, and the recorded number has to be the real one or the
/// whole log is worthless.
struct TodaysTally: Equatable, Sendable {
    /// Today's cap, off the plan.
    var ceilingMg: Double
    /// Logged so far, sources only.
    var loggedMg: Double
    /// The pending selection, sources only. Zero when nothing is chosen or when
    /// what is chosen is a treatment.
    var pendingMg: Double

    init(entries: [StoredCheckIn], pending: PendingEntry?, ceilingMg: Double) {
        self.ceilingMg = ceilingMg
        loggedMg = entries
            .filter { $0.ledger == .source }
            .reduce(0) { $0 + $1.totalMg }
        pendingMg = pending.map { $0.key.ledger == .source ? $0.totalMg : 0 } ?? 0
    }

    /// Where logging the pending entry would leave them.
    var projectedMg: Double { loggedMg + pendingMg }

    var isOver: Bool { projectedMg > ceilingMg }

    /// How far over, or zero. Never negative — "0 mg over" is not a thing to
    /// say to somebody who is under.
    var overByMg: Double { max(0, projectedMg - ceilingMg) }

    // MARK: - The meter

    /// The logged run, up to the ceiling.
    ///
    /// These three are **segments of the bar, not shares of the total**, and
    /// the distinction is the whole of this section. Under the cap the bar is
    /// the cap and they simply add up. Over it the bar rescales to the
    /// projected total so the overflow has somewhere to be drawn — the board
    /// shows it as a red tail rather than a full bar, because "the meter shows
    /// the overflow honestly" and a bar pinned at 100% would hide exactly the
    /// number that matters.
    ///
    /// Splitting them this way is what keeps the milligrams past the ceiling in
    /// one segment. Reporting each quantity's whole share instead would draw
    /// the overflow twice whenever the pending tap is the thing that goes over.
    var loggedFraction: Double { fraction(of: min(loggedMg, ceilingMg)) }

    /// The pending run — only the part of it that still fits under the ceiling.
    var pendingFraction: Double {
        fraction(of: max(0, min(projectedMg, ceilingMg) - loggedMg))
    }

    /// Everything past the ceiling, wherever it came from.
    var overflowFraction: Double { fraction(of: overByMg) }

    private func fraction(of amount: Double) -> Double {
        let span = max(ceilingMg, projectedMg)
        guard span > 0 else { return 0 }
        return amount / span
    }

    // MARK: - What it says

    /// The line under the meter.
    ///
    /// Three sentences for three states, and the numbers are the only thing
    /// that differs — no encouragement, no verdict.
    var readout: String {
        if isOver {
            return "\(overByMg.clean) mg over today's cap"
        }
        if pendingMg > 0 {
            return "puts you at \(projectedMg.clean) — today's ceiling is \(ceilingMg.clean) mg"
        }
        return "\(loggedMg.clean) of \(ceilingMg.clean) mg today"
    }

    /// Shown beside the button when the tap about to happen would go over.
    ///
    /// A question, not a warning: it is asked before logging and answered by
    /// logging. Nil when there is nothing to ask about — including when they
    /// are *already* over, where the decision has been made and asking again
    /// would be the app relitigating it.
    var questionBeforeLogging: String? {
        guard isOver, loggedMg <= ceilingMg, pendingMg > 0 else { return nil }
        return "This one takes you over today's cap. Log it anyway?"
    }

    /// Shown after logging has put them over.
    ///
    /// "Noted, not judged" is the whole design position in three words, and the
    /// second half is the part that matters: going over does not move the plan.
    /// Tomorrow's cap is on a schedule, not on a performance.
    var noteAfterGoingOver: String? {
        guard loggedMg > ceilingMg else { return nil }
        return "Logged. You're \((loggedMg - ceilingMg).clean) mg over — noted, not judged. Tomorrow's cap still drops."
    }
}
