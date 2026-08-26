import Foundation

/// The tracking card's middle row: today, counted per key.
///
/// The figure above says what the day came to; this says what it was made of —
/// "2 pouches · 1 gum · 0 lozenges" — one column per key on the pad, including
/// the ones that went untouched. A zero is the point of showing them: the day
/// somebody reached for the gum instead of the pouches is told entirely by
/// which column the count landed in.
struct DayBreakdown: Equatable, Sendable {
    /// One key's day: what to call it, how many, and at what strength.
    struct Column: Equatable, Sendable {
        /// The key's own id, so a list can tell two same-form columns apart.
        let keyID: Int
        /// "pouches", "gum" — the form's counted word, not the key's label.
        /// The board writes the category here; the product name is on the log's
        /// rows, where there is room for it.
        let word: String
        /// Times taken today, quantities included: one tap × 2 is two.
        let count: Int
        /// "3 mg" — the key's per-unit strength, not the column's total. The
        /// total is the figure above; this says what one of them is.
        let strengthText: String

        var countText: String { "\(count)" }
        /// A column that went untouched draws its strength faint.
        var isUntouched: Bool { count == 0 }
    }

    let columns: [Column]

    /// Sources first, then treatment, each run in pad order.
    ///
    /// The opposite of the pad, and deliberately: the pad puts what helps
    /// first, but this card is *nicotine tracking* — the count that matters is
    /// the one against the ceiling, so what is being quit leads.
    ///
    /// Counted by `pad_key_id`, which means a row whose key has since left the
    /// pad lands in no column. The figure above still counts it; the columns
    /// are a claim about the pad as it stands, not a second total.
    init(pad: Pad, entries: [StoredCheckIn]) {
        var taken: [Int: Int] = [:]
        for entry in entries {
            guard let id = entry.padKeyID else { continue }
            taken[id, default: 0] += entry.quantity
        }
        columns = (pad.sources + pad.treatment).map { key in
            let count = taken[key.id] ?? 0
            return Column(
                keyID: key.id,
                word: key.form.counted(count),
                count: count,
                strengthText: "\(key.mg.clean) mg"
            )
        }
    }
}

extension PadForm {
    /// The word for some number of this form: "1 lozenge", "2 lozenges".
    ///
    /// "Gum" and "dip" do not pluralise — two pieces of gum are still gum — and
    /// `.other` says "logged", because the app does not know what the thing is
    /// and guessing a noun would put a word in the user's mouth.
    func counted(_ count: Int) -> String {
        switch self {
        case .gum: return "gum"
        case .dip: return "dip"
        case .other: return "logged"
        case .patch: return count == 1 ? "patch" : "patches"
        case .lozenge: return count == 1 ? "lozenge" : "lozenges"
        case .inhaler: return count == 1 ? "inhaler" : "inhalers"
        case .spray: return count == 1 ? "spray" : "sprays"
        case .pouch: return count == 1 ? "pouch" : "pouches"
        case .vape: return count == 1 ? "vape" : "vapes"
        case .cigarette: return count == 1 ? "cigarette" : "cigarettes"
        }
    }
}
