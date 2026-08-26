import Foundation
import Testing
@testable import Taper

private final class FakeCheckInLog: CheckInWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()
    private struct State {
        var logged: [CheckInDraft] = []
        var fails = false
    }
    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var logged: [CheckInDraft] { lock.withLock { state.logged } }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        try lock.withLock {
            if state.fails { throw URLError(.notConnectedToInternet) }
            state.logged.append(draft)
            return StoredCheckIn(id: state.logged.count, ledger: draft.ledger,
                                 label: draft.label, form: draft.form, mg: draft.mg,
                                 quantity: draft.quantity, loggedOn: "2026-08-26",
                                 createdAt: Date(timeIntervalSince1970: 0), padKeyID: nil)
        }
    }
}

private func gum(_ strengths: [Double] = [2, 4]) -> NRTResult {
    NRTResult(brand: "Nicorette gum, ice mint", labeler: "Haleon",
              form: .gum, strengths: strengths.map { (mg: $0, ndc: "0135-\($0)") })
}

/// Covers L5's state: the strength in hand, the count, and the check-in they
/// become.
@MainActor
struct ProductDetailRecordTests {
    @Test("the default strength is the lowest, because this app tapers")
    func thePresumptuousDefaultPresumesLess() {
        #expect(ProductDetailRecord(product: gum([4, 2]), store: nil).mg == 2)
    }

    @Test("a strength the label does not come in cannot be chosen")
    func theChipsAreTheWholeVocabulary() {
        let record = ProductDetailRecord(product: gum(), store: nil)
        record.choose(3)
        #expect(record.mg == 2, "a strength off the label was accepted")
        record.choose(4)
        #expect(record.mg == 4)
    }

    @Test("the count is clamped to what the column accepts")
    func aRejectableNumberIsNotBuildable() {
        let record = ProductDetailRecord(product: gum(), store: nil)
        record.add(-1)
        #expect(record.quantity == 1)
        record.add(30)
        #expect(record.quantity == 20)
    }

    @Test("logging writes the product as a keyless treatment row")
    func theDoseIsRealAndTheKeyIsNot() async {
        let log = FakeCheckInLog()
        let record = ProductDetailRecord(product: gum(), store: log)
        record.choose(4)
        record.add(1)

        #expect(await record.log() != nil)

        let written = log.logged.first
        #expect(written?.padKeyID == nil, "a catalogue log cited a key nobody pressed")
        #expect(written?.ledger == .treatment, "licensed NRT landed on the ledger the cap counts")
        #expect(written?.label == "Nicorette gum, ice mint")
        #expect(written?.mg == 4)
        #expect(written?.quantity == 2)
    }

    @Test("one screen logs one row, and a failure can be retried")
    func loggedIsTerminalAndFailedIsNot() async {
        let log = FakeCheckInLog()
        let record = ProductDetailRecord(product: gum(), store: log)

        log.fails = true
        #expect(await record.log() == nil)
        #expect(record.failureText == "Couldn't log that. Try again.")

        log.fails = false
        #expect(await record.log() != nil, "a failed log could not be retried")
        #expect(record.status == .logged)
        #expect(await record.log() == nil, "a spent screen wrote a second row")
        #expect(log.logged.count == 1)
    }

    @Test("the label speaks in its own words")
    func theFactsAreTheLabels() {
        let gumRecord = ProductDetailRecord(product: gum(), store: nil)
        #expect(gumRecord.activeIngredientText == "Nicotine polacrilex 2 mg")
        #expect(gumRecord.ingredientHeading == "Active ingredient (per piece)")
        #expect(gumRecord.quantityText == "1 piece")
        gumRecord.add(1)
        #expect(gumRecord.quantityText == "2 pieces")
        #expect(gumRecord.totalText == "4 mg")

        let patch = NRTResult(brand: "NicoDerm CQ", labeler: "Haleon",
                              form: .patch, strengths: [(mg: 14.0, ndc: "x")])
        let patchRecord = ProductDetailRecord(product: patch, store: nil)
        #expect(patchRecord.activeIngredientText == "Nicotine 14 mg")
        #expect(patchRecord.ingredientHeading == "Active ingredient (per patch)")

        #expect(gumRecord.subtitleText == "Stop smoking aid · From the FDA label library",
                "the screen claimed a marketing category the result does not carry")
    }

    @Test("a spray's concentration is not a per-spray dose, and cannot be logged as one")
    func tenMilligramsPerMLIsNotOneSpray() async {
        // openFDA carries Nicotrol NS as 10 mg — per mL. One actuation
        // delivers about 0.5 mg, so counting sprays at the catalogue's number
        // would record twenty times the dose.
        let log = FakeCheckInLog()
        let spray = NRTResult(brand: "Nicotrol NS", labeler: "Pfizer",
                              form: .spray, strengths: [(mg: 10.0, ndc: "x")])
        let record = ProductDetailRecord(product: spray, store: log)

        #expect(record.isCountable == false)
        #expect(record.ingredientHeading == "Active ingredient (as labeled)",
                "a concentration was named per spray")
        #expect(await record.log() == nil, "a spray was logged at its concentration")
        #expect(log.logged.isEmpty)
    }
}
