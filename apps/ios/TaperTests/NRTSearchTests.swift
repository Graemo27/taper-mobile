import Foundation
import Testing
@testable import Taper

/// Covers how the licensed catalogue's rows become the rows a person reads.
@MainActor
struct NRTSearchTests {
    private func product(_ brand: String, _ form: PadForm, _ mg: Double,
                         ndc: String? = nil, labeler: String = "nicotine polacrilex") -> NRTProduct {
        NRTProduct(id: ndc ?? "\(brand)-\(mg)", brand: brand, labeler: labeler, form: form, mg: mg)
    }

    @Test("one brand in two strengths is one row with two chips")
    func aStrengthIsNotAProduct() {
        // openFDA lists every strength as its own product. Offering both as
        // results asks somebody to choose a dose before they have chosen a
        // product, which is backwards — the dose depends on the product.
        let rows = SupabaseNRTSearch.grouped([
            product("Nicorette gum, ice mint", .gum, 4),
            product("Nicorette gum, ice mint", .gum, 2),
        ])

        #expect(rows.count == 1, "two strengths of one gum came back as two products")
        #expect(rows.first?.strengths.map(\.mg) == [2, 4], "the chips are not low to high")
    }

    @Test("the same brand in two forms stays two rows")
    func aFormIsAProduct() {
        // A gum and a lozenge are different things to put in your mouth, and
        // the pad files them under different keys.
        let rows = SupabaseNRTSearch.grouped([
            product("Nicorette", .gum, 4),
            product("Nicorette", .lozenge, 4),
        ])

        #expect(rows.count == 2)
        #expect(Set(rows.map(\.form)) == [.gum, .lozenge])
    }

    @Test("each strength keeps the code it came from")
    func aChipCarriesItsOwnProduct() {
        // The chip is what a key gets built from, and a key needs the exact
        // product rather than the number — two brands' 4 mg gums are not
        // interchangeable rows in a drug catalogue.
        let rows = SupabaseNRTSearch.grouped([
            product("Nicorette gum", .gum, 2, ndc: "0135-0166"),
            product("Nicorette gum", .gum, 4, ndc: "0135-0177"),
        ])

        #expect(rows.first?.strengths.map(\.ndc) == ["0135-0166", "0135-0177"])
    }

    @Test("a repeated strength is one chip")
    func twoCodesOneDoseIsOneChip() {
        // A brand can list the same milligrams under two codes — a repack, or a
        // second package size. Two identical chips read as a rendering fault.
        let rows = SupabaseNRTSearch.grouped([
            product("Nicorette gum", .gum, 4, ndc: "a"),
            product("Nicorette gum", .gum, 4, ndc: "b"),
        ])

        #expect(rows.first?.strengths.map(\.mg) == [4])
    }

    @Test("the catalogue's order is kept")
    func relevanceIsNotResorted() {
        // openFDA returns these by its own relevance. Re-sorting alphabetically
        // here would put the app's opinion in front of the label's, and the
        // thing somebody typed is usually the thing that comes back first.
        let rows = SupabaseNRTSearch.grouped([
            product("Zonnic", .gum, 4),
            product("Nicorette", .gum, 4),
        ])

        #expect(rows.map(\.brand) == ["Zonnic", "Nicorette"], "the results were re-ordered")
    }

    @Test("a field with nothing in it is not a search")
    func whitespaceIsNotAQuery() {
        // The function answers 400 to an empty query, so sending one buys a
        // round trip whose only outcome is an error — and a field holding two
        // spaces is empty as far as a drug catalogue is concerned.
        #expect(SupabaseNRTSearch.asked(from: "   ").isEmpty)
        #expect(SupabaseNRTSearch.asked(from: "\n\t").isEmpty)
        #expect(SupabaseNRTSearch.asked(from: "  nicorette  ") == "nicorette")
    }

    @Test("a row says what kind of thing it is")
    func theDetailNamesTheForm() {
        let gum = SupabaseNRTSearch.grouped([product("Nicorette gum", .gum, 4)]).first

        #expect(gum?.detailText == "Gum · nicotine polacrilex")

        // And a product with no labeler still says the form rather than
        // trailing a separator with nothing after it.
        let bare = SupabaseNRTSearch.grouped([product("Own brand", .lozenge, 2, labeler: "")]).first
        #expect(bare?.detailText == "Lozenge")
    }
}
