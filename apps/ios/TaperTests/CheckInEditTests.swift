import Foundation
import Testing
@testable import Taper

/// Covers what the edit screen says about one check-in, including the two
/// halves the board only draws one of.
@MainActor
struct CheckInEditTests {
    private func entry(
        ledger: PadKey.Ledger = .source, form: PadForm = .pouch,
        label: String = "Pouch", mg: Double = 3, quantity: Int = 1
    ) -> StoredCheckIn {
        StoredCheckIn(id: 1, ledger: ledger, label: label, form: form,
                      mg: mg, quantity: quantity, loggedOn: PlanDay.wireFormat(.testMoment), createdAt: .testMoment)
    }

    private func view(_ entry: StoredCheckIn, failure: RemovalFailure? = nil,
                      isRemoving: Bool = false) -> CheckInEditView {
        CheckInEditView(entry: entry, failure: failure, isRemoving: isRemoving,
                        onRemove: {}, onBack: {})
    }

    @Test("a treatment is not told it counts against the cap")
    func treatmentIsNotCountedAtAnyone() {
        // The board only draws the source case. Reusing its sentence for a
        // patch would tell somebody the thing carrying them under the cap is
        // spending it — which is the one misreading this whole ledger split
        // exists to prevent.
        #expect(view(entry(ledger: .source)).contributionText == "Counts toward today")
        #expect(
            view(entry(ledger: .treatment, form: .patch, label: "Patch", mg: 14)).contributionText
                == "Doesn't count toward your cap"
        )
    }

    @Test("the per-unit line appears only when there is more than one")
    func oneOfSomethingNeedsNoArithmetic() {
        // "1 × 3 mg each" is the title and the figure below it repeated. The
        // line earns its place only when the total and the strength differ.
        #expect(view(entry(quantity: 1)).perUnitText == nil)
        #expect(view(entry(mg: 1.2, quantity: 3)).perUnitText == "3 × 1.2 mg each")
    }

    @Test("the subtitle says when, and which kind, in that order")
    func theSubtitleReadsAsAnAside() {
        // Lowercase here and capitalised on the list row, deliberately: on a
        // row the form is the category heading, and here it is an aside after
        // the time.
        let text = view(entry(form: .gum, label: "Nicorette ice mint", mg: 2)).whenText

        #expect(text.hasPrefix("Today at "))
        #expect(text.hasSuffix(" · gum"))
    }

    @Test("the note about removing says what it gives back")
    func theNoteIsTheReasonThisIsAScreen() {
        // The sentence is why this is a screen rather than a swipe. Somebody
        // who mis-tapped needs to be told the milligrams come back, and a
        // gesture cannot say anything.
        let source = view(entry(ledger: .source)).removalNote

        #expect(source.contains("gives the mg back"))
        #expect(source.contains("No judgement"))
    }

    @Test("removing a treatment is not promised milligrams back")
    func theNoteAgreesWithTheLedgerAboveIt() {
        // A patch never spent anything, so removing it changes the record and
        // not the number. The source sentence would sit two lines under
        // "Doesn't count toward your cap" and contradict it — and would tell
        // somebody their cap grows when they delete their treatment, which is
        // the misreading the whole ledger split exists to prevent.
        let treatment = view(entry(ledger: .treatment, form: .patch, label: "Patch", mg: 14))

        #expect(!treatment.removalNote.contains("gives the mg back"), "a patch was promised its mg back")
        #expect(treatment.removalNote.contains("doesn't change"))
        #expect(treatment.removalNote.contains("No judgement"), "the reassurance was dropped")
    }

    @Test("a failure about another row is not shown on this one")
    func anApologyIsAddressedToSomebody() {
        // `removeFailure` lives on the record, which outlives this screen: a
        // removal that fails, a step back, and a different row opened would
        // otherwise greet somebody with an apology for something nobody did to
        // the row in front of them.
        let mine = RemovalFailure(entryID: 1, message: "Couldn't remove that.")
        let theirs = RemovalFailure(entryID: 99, message: "Couldn't remove that.")

        #expect(view(entry(), failure: mine).failureText == "Couldn't remove that.")
        #expect(view(entry(), failure: theirs).failureText == nil, "another row's failure was shown")
        #expect(view(entry(), failure: nil).failureText == nil)
    }
}
