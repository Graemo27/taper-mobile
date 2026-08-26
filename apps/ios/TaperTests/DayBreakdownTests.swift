import Foundation
import Testing
@testable import Taper

private func key(_ id: Int, _ form: PadForm, mg: Double, position: Int = 0) -> StoredPadKey {
    StoredPadKey(id: id, form: form, label: form.label, mg: mg, position: position, ndc: nil)
}

private func row(
    _ id: Int, key: Int?, form: PadForm = .pouch, mg: Double = 3, quantity: Int = 1
) -> StoredCheckIn {
    StoredCheckIn(id: id, ledger: form.ledger, label: form.label, form: form,
                  mg: mg, quantity: quantity, loggedOn: "2026-08-26",
                  createdAt: Date(timeIntervalSince1970: 0), padKeyID: key)
}

/// Covers the tracking card's middle row: today, counted per key.
struct DayBreakdownTests {
    @Test("every key gets a column, and an untouched one counts zero")
    func theZeroIsThePoint() {
        // The day somebody reached for the gum instead of the pouches is told
        // entirely by which column the count landed in — so the untouched
        // column has to be there for the used one to mean anything.
        let pad = Pad(keys: [
            key(1, .gum, mg: 2, position: 0),
            key(2, .lozenge, mg: 1, position: 1),
            key(3, .pouch, mg: 3, position: 0),
        ])
        let breakdown = DayBreakdown(pad: pad, entries: [
            row(10, key: 3), row(11, key: 3), row(12, key: 1),
        ])

        #expect(breakdown.columns.map(\.count) == [2, 1, 0])
        #expect(breakdown.columns.map(\.isUntouched) == [false, false, true])
        #expect(breakdown.columns.map(\.word) == ["pouches", "gum", "lozenges"])
        #expect(breakdown.columns.map(\.strengthText) == ["3 mg", "2 mg", "1 mg"])
    }

    @Test("sources lead, then treatment, each in pad order")
    func whatCountsAgainstTheCeilingComesFirst() {
        // The opposite of the pad, and deliberately: the pad puts what helps
        // first, but this card is nicotine tracking, and the count that
        // matters is the one against the ceiling.
        let pad = Pad(keys: [
            key(1, .patch, mg: 21, position: 0),
            key(2, .lozenge, mg: 4, position: 1),
            key(3, .pouch, mg: 6, position: 0),
            key(4, .vape, mg: 2, position: 1),
        ])

        #expect(DayBreakdown(pad: pad, entries: []).columns.map(\.keyID) == [3, 4, 1, 2])
    }

    @Test("a tap of two is two, not one")
    func quantitiesAreCountedOut() {
        let pad = Pad(keys: [key(1, .pouch, mg: 3)])
        let breakdown = DayBreakdown(pad: pad, entries: [
            row(10, key: 1, quantity: 2), row(11, key: 1),
        ])

        #expect(breakdown.columns.first?.count == 3)
    }

    @Test("a row whose key left the pad lands in no column")
    func theColumnsAreAClaimAboutThePadAsItStands() {
        // `on delete set null` empties `pad_key_id` when a key is removed. The
        // figure above still counts the row; a column for it would need a key
        // that no longer exists to hang it on.
        let pad = Pad(keys: [key(1, .pouch, mg: 3)])
        let breakdown = DayBreakdown(pad: pad, entries: [
            row(10, key: nil, mg: 6), row(11, key: 1),
        ])

        #expect(breakdown.columns.map(\.count) == [1])
    }

    @Test("an urge is not a column either")
    func gettingThroughOneIsCountedElsewhere() {
        // Urges cite no key, so the same rule covers them — but by design
        // rather than by accident: their line is under the row, in words.
        let pad = Pad(keys: [key(1, .lozenge, mg: 4)])
        let urge = StoredCheckIn(
            id: 10, ledger: .treatment, label: CheckInDraft.urgeLabel, form: .other,
            mg: 0, quantity: 1, loggedOn: "2026-08-26",
            createdAt: Date(timeIntervalSince1970: 0), padKeyID: nil
        )

        #expect(DayBreakdown(pad: pad, entries: [urge]).columns.map(\.count) == [0])
    }

    @Test("the counted words are English at every count")
    func gumDoesNotPluralise() {
        #expect(PadForm.lozenge.counted(1) == "lozenge")
        #expect(PadForm.lozenge.counted(0) == "lozenges")
        #expect(PadForm.gum.counted(2) == "gum")
        #expect(PadForm.dip.counted(2) == "dip")
        #expect(PadForm.cigarette.counted(2) == "cigarettes")
        #expect(PadForm.other.counted(2) == "logged",
                "the app guessed a noun for a thing the user named")
    }
}
