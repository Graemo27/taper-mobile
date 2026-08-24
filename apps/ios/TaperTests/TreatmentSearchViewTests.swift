import Foundation
import Testing
@testable import Taper

private func result(_ brand: String, _ labeler: String, _ form: PadForm,
                    _ mg: Double...) -> NRTResult {
    NRTResult(brand: brand, labeler: labeler, form: form,
              strengths: mg.map { (mg: $0, ndc: "\(brand)-\($0)") })
}

/// Covers what the search screen says about itself: the line under the field,
/// which of its states reads as a fault, and what a result row speaks.
@MainActor
struct TreatmentSearchViewTests {
    private func note(_ status: SearchStatus) -> String? {
        TreatmentSearchView.note(for: status)
    }

    @Test("the field says what the catalogue is before anything is typed")
    func restingNamesTheLicensedForms() {
        // The rule the backend enforces has to be legible at the point of
        // searching. Somebody who came here to find their pouches should be
        // told what this list is for rather than left to conclude the app
        // cannot find a brand it will never carry.
        let note = note(.resting)
        #expect(note?.contains("Licensed nicotine replacement only") == true)
        for form in ["gum", "lozenge", "patch", "inhaler", "spray"] {
            #expect(note?.contains(form) == true, "resting did not name \(form)")
        }
    }

    @Test("nothing found and nothing reached do not read alike")
    func anEmptyShelfIsNotAFault() {
        // One of these has a retry and the other does not. The failure is the
        // only state drawn in the caution colour, so a search that simply
        // found nothing must not borrow it.
        #expect(note(.noMatches)?.contains("Nothing licensed matched") == true)
        #expect(TreatmentSearchView.isFailure(.noMatches) == false,
                "no matches was drawn as a failure")

        let broken = SearchStatus.unavailable("Couldn't reach the product list.")
        #expect(note(broken) == "Couldn't reach the product list.")
        #expect(TreatmentSearchView.isFailure(broken),
                "a failed lookup was not drawn as a failure")
    }

    @Test("a count of one is not written as one matches")
    func theCountAgreesWithItsNoun() {
        #expect(note(.results([result("Nicorette", "GSK", .gum, 2)]))?
            .hasPrefix("1 match ·") == true)
        #expect(note(.results([
            result("Nicorette", "GSK", .gum, 2),
            result("NicoDerm", "GSK", .patch, 21),
        ]))?.hasPrefix("2 matches ·") == true)
    }

    @Test("the results line says where the numbers came from")
    func resultsNameTheirSource() {
        // A list of nicotine products has to say plainly that it is a licensed
        // catalogue and not a shop.
        let line = note(.results([result("Nicorette", "GSK", .gum, 2)]))
        #expect(line?.contains("FDA drug facts") == true)
    }

    @Test("a row speaks every strength, not just the first")
    func theChipsAreSpokenTo() {
        // The chips are what decides which product a row is. Sighted readers
        // get all of them at once; a listener gets whatever the label says, so
        // a label naming only the brand would hide the choice being made.
        let spoken = TreatmentResultRow.spokenText(
            for: result("Nicorette", "nicotine polacrilex", .gum, 2, 4))
        #expect(spoken == "Nicorette, Gum · nicotine polacrilex, available in 2 milligrams and 4 milligrams")
    }

    @Test("a product with no labeler is not read out with a dangling separator")
    func anUnnamedLabelerLeavesNoGap() {
        let spoken = TreatmentResultRow.spokenText(for: result("Habitrol", "", .lozenge, 4))
        #expect(spoken == "Habitrol, Lozenge, available in 4 milligrams")
    }
}

/// Covers the copy on the screen that turns a result into a key.
@MainActor
struct NewTreatmentKeyViewTests {
    @Test("the strength line names the form's own unit")
    func aPatchIsNotMeasuredPerPiece() {
        // A patch is worn for a day; a lozenge is taken. "Mg per patch" invites
        // someone to count them like pieces.
        #expect(NewTreatmentKeyView.strengthTitle(for: .patch) == "Mg per 24 hours")
        #expect(NewTreatmentKeyView.strengthTitle(for: .lozenge) == "Mg per lozenge")
        #expect(NewTreatmentKeyView.strengthTitle(for: .gum) == "Mg per gum")
    }

    @Test("a single-strength product does not promise a choice")
    func oneStrengthSaysSo() {
        // The stepper has nowhere to go on a one-strength label, and a line
        // reading "1 strengths" would look like a bug in the catalogue.
        #expect(NewTreatmentKeyView.strengthNote(count: 1) == "The only strength on this label")
        #expect(NewTreatmentKeyView.strengthNote(count: 3).contains("3 strengths"))
    }
}

