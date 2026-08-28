import Foundation
import Testing
@testable import Taper

private final class FakeCheckInLog: CheckInWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var state = State()
    private struct State {
        /// Every attempt, landed or not — a store that fails still sent one.
        var logged: [CheckInDraft] = []
        /// The attempts that became rows.
        var committed: [CheckInDraft] = []
        var fails = false
    }
    var fails: Bool {
        get { lock.withLock { state.fails } }
        set { lock.withLock { state.fails = newValue } }
    }
    var logged: [CheckInDraft] { lock.withLock { state.logged } }
    var committed: [CheckInDraft] { lock.withLock { state.committed } }

    func log(_ draft: CheckInDraft) async throws -> StoredCheckIn {
        try lock.withLock {
            // Recorded before the refusal, because a store that fails still
            // sent the request — and what a retry *said* is the thing these
            // tests are about.
            state.logged.append(draft)
            if state.fails { throw URLError(.notConnectedToInternet) }
            state.committed.append(draft)
            return StoredCheckIn(id: state.committed.count, ledger: draft.ledger,
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
        #expect(log.committed.count == 1, "more than one row reached the store")
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
        #expect(record.uncountableNote == ProductDetailRecord.sprayNote)
        #expect(record.totalText == nil, "a concentration was dressed as a total")
    }

    @Test("a label with no stated strength has no number to log")
    func zeroIsNotADoseEither() async {
        // The dangerous half of this: a keyless zero-milligram treatment row
        // is the exact shape `isUrge` reads back as a craving outlasted, so a
        // catalogue gap logged at zero would be filed as willpower.
        let log = FakeCheckInLog()
        let blank = NRTResult(brand: "Mystery gum", labeler: "Nobody",
                              form: .gum, strengths: [])
        let record = ProductDetailRecord(product: blank, store: log)

        #expect(record.isCountable == false)
        #expect(record.uncountableNote == ProductDetailRecord.noStrengthNote)
        #expect(record.quantityText == nil)
        #expect(await record.log() == nil, "a strengthless label was logged at zero")
        #expect(log.logged.isEmpty)

        #expect(CheckInDraft.product(brand: "x", form: .gum, mg: 0,
                                     quantity: 1, on: .testMoment) == nil,
                "the draft boundary let a zero-milligram product through")
    }

    @Test("a retry of a catalogue log is the same write, clock notwithstanding")
    func theLabelRetryKeepsItsIdentity() async {
        // The third path that rebuilds its draft on retry, and the one where a
        // duplicate is a real dose counted twice against a real cap.
        let log = FakeCheckInLog()
        log.fails = true
        let clock = ProductClock(Date(timeIntervalSince1970: 1_780_000_000))
        let gum = NRTResult(brand: "Nicorette", labeler: "Haleon",
                            form: .gum, strengths: [(mg: 2.0, ndc: "x")])
        let record = ProductDetailRecord(product: gum, store: log, now: { clock.now })

        #expect(await record.log() == nil)
        clock.now = clock.now.addingTimeInterval(30)
        log.fails = false
        #expect(await record.log() != nil)

        #expect(log.logged.count == 2, "the retry never reached the store")
        #expect(log.logged[0].requestID == log.logged[1].requestID,
                "a retry half a minute later introduced itself as a different write")
    }
}

/// A movable clock, so a retry happens at a different instant from the attempt
/// it repeats — which in the app it always does.
private final class ProductClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}
