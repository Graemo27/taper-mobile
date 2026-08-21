import Foundation
import Testing
@testable import Taper

/// Covers the pad as onboarding leaves it.
///
/// The run already asks for every field a key needs, so the pad can be seeded
/// rather than met empty — and the failure this suite is mostly about is the
/// quiet one: a completed run producing a pad with nothing on it, which looks
/// like a finished onboarding and behaves like a broken app.
struct PadSeedTests {
    /// A run that named pouches and reached a plan.
    private func answers(
        sources: [NicotineSource] = [.pouches],
        treatments: [TreatmentForm] = [.patch, .lozenge]
    ) -> OnboardingAnswers {
        let answers = OnboardingAnswers()
        for source in sources { answers.toggle(source) }
        answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 6 }
        answers.strengths[.nrt] = StrengthOption.nrt.first { $0.mg == 4 }
        answers.setAmount(8, for: .pouches)
        answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
        answers.usesWhenIllInBed = true
        for form in treatments { answers.toggle(form) }
        return answers
    }

    private func plan(for answers: OnboardingAnswers) -> TaperPlan {
        TaperPlanner.plan(for: answers.taperInput!)
    }

    @Test("a completed run never leaves the pad empty")
    func aFinishedRunHasSomethingToTap() {
        // The defect shape this guards: onboarding finishes, a plan is saved,
        // and the user lands on a home screen with no key to tap. Every path
        // that got here named at least one source — a run with none cannot
        // produce a cap, and a run with no cap cannot produce a plan.
        let answers = answers()
        let keys = answers.padKeys(with: plan(for: answers).replacement)

        #expect(!keys.isEmpty)
        #expect(keys.contains { $0.ledger == .source })
    }

    @Test("every source the user named gets a key, in the order they were asked")
    func eachSourceIsOnThePad() {
        let answers = answers(sources: [.pouches, .cigarettes, .vape])
        let sources = answers.padKeys(with: plan(for: answers).replacement).filter { $0.ledger == .source }

        let named: [NicotineSource] = [.pouches, .cigarettes, .vape]
        #expect(sources.map(\.form) == named.map(\.padForm))
        #expect(sources.map(\.label) == ["Pouches", "Cigarettes", "Vape"])
    }

    @Test("a printed strength is used where there is one, an estimate where there is not")
    func strengthsFollowTheSameRuleTheCapDoes() {
        // The precedence has to match `startingCapMg`, or the pad prices a
        // pouch differently from the plan that was built on it — and the two
        // numbers are subtracted from each other every time somebody logs.
        let answers = answers(sources: [.pouches, .cigarettes])
        let sources = answers.padKeys(with: plan(for: answers).replacement).filter { $0.ledger == .source }

        #expect(sources.first { $0.form == .pouch }?.mg == 6, "the strength the user read off the tin")
        #expect(sources.first { $0.form == .cigarette }?.mg == NicotineSource.cigarettes.estimatedMgPerUnit)
    }

    @Test("every key is priced at the figure the cap was built from")
    func thePadAndThePlanAgreeOnWhatOneIsWorth() {
        // The property that matters, rather than the rule that implements it.
        // The cap is the sum of these per-unit figures across sources, and
        // every log is subtracted from that cap using the figure on the key —
        // so a pad priced by a different rule makes the ceiling unreachable or
        // trivially met, with nothing on screen to explain either.
        let answers = answers(sources: [.pouches, .cigarettes, .vape, .dip, .nrt, .other])
        let sources = answers.padKeys(with: plan(for: answers).replacement).filter { $0.ledger == .source }

        #expect(sources.count == answers.orderedSources.count, "a source the cap counted has no key")
        for (key, source) in zip(sources, answers.orderedSources) {
            #expect(key.mg == answers.mgPerUnit(for: source))
        }
        // And the cap really is that sum, so the agreement above is worth
        // something rather than two views of one unused number.
        let fromKeys = zip(sources, answers.orderedSources)
            .reduce(0.0) { $0 + $1.0.mg * Double(answers.amount(for: $1.1)) }
        #expect(fromKeys == answers.startingCapMg)
    }

    @Test("a strength the user gave beats one the app estimated")
    func aStatedFigureWinsOverAnEstimate() {
        // Unreachable through the UI today: only pouches and NRT are asked for
        // a printed strength, and neither carries an estimate, so no source can
        // hold both. Written anyway because it pins the contract of the one
        // function the cap and the pad now share — if `usesPerUnitStrength`
        // ever widens, this is the behaviour both of them inherit, and it
        // inherits it in one place rather than two.
        let answers = answers(sources: [.cigarettes])
        #expect(NicotineSource.cigarettes.estimatedMgPerUnit != nil, "the fixture needs a fallback to beat")

        answers.strengths[.cigarettes] = StrengthOption.nrt.first { $0.mg == 4 }

        #expect(answers.mgPerUnit(for: .cigarettes) == 4)
        let key = answers.padKeys(with: plan(for: answers).replacement).first { $0.form == .cigarette }
        #expect(key?.mg == 4)
        // Both sides of the shared call, not just the pad's. A cap still built
        // on the estimate while the key is priced on the stated figure is the
        // divergence this whole change exists to prevent.
        #expect(answers.startingCapMg == 4 * Double(answers.amount(for: .cigarettes)))
    }

    @Test("licensed gum being quit is filed as a source, not as a treatment")
    func quittingNRTIsSomethingToQuit() {
        // Someone can arrive already on gum and want off it. The two ledgers
        // must not be inferred from each other: filing this as treatment would
        // put the thing they are quitting on the list of what is helping them
        // quit, and the cap would then be measured against itself.
        let answers = answers(sources: [.nrt], treatments: [.lozenge])
        let keys = answers.padKeys(with: plan(for: answers).replacement)

        let quitting = keys.first { $0.label == NicotineSource.nrt.label }
        #expect(quitting?.ledger == .source)
        // `.other`, because the source ledger's forms are tobacco products.
        // The label is what carries the meaning.
        #expect(quitting?.form == .other)
    }

    @Test("the treatment keys are the ones chosen, at the strengths the plan committed to")
    func treatmentKeysQuoteThePlan() {
        let answers = answers(treatments: [.patch, .gum])
        let plan = plan(for: answers)
        let treatment = answers.padKeys(with: plan.replacement).filter { $0.ledger == .treatment }

        #expect(treatment.map(\.form) == [.patch, .gum], "not the set's arbitrary order")
        #expect(treatment.first { $0.form == .patch }?.mg == Double(plan.replacement.patchMg!))
        #expect(treatment.first { $0.form == .gum }?.mg == Double(plan.replacement.fastActingMg))
    }

    @Test("someone who declined a treatment gets none on their pad")
    func decliningIsHonoured() {
        // Forms are ticked *first* and then declined, which is the order a
        // user can actually produce — go back a screen and change your mind.
        // Declining with an empty set proves nothing: the seed would be empty
        // either way, and the earlier version of this test passed against a
        // build that ignored the refusal entirely.
        let answers = answers(treatments: [.patch, .lozenge])
        answers.deferTreatment()
        let keys = answers.padKeys(with: plan(for: answers).replacement)

        #expect(keys.allSatisfy { $0.ledger == .source })
        #expect(!keys.isEmpty, "declining a treatment must not empty the whole pad")
    }

    @Test("a form the plan has no dose for gets no key")
    func aPatchWithoutAStrengthIsNotSeeded() {
        // O5a offers all three forms whatever the plan recommends, so a light
        // intake can tick a patch that was never suggested — and its row is
        // shown with no milligrams on it. A key needs a number, and the only
        // one available would be invented.
        let answers = answers(treatments: [.patch, .lozenge])
        answers.setAmount(1, for: .pouches)
        let plan = plan(for: answers)
        #expect(plan.replacement.patchMg == nil, "the fixture must be light enough to warrant no patch")

        let treatment = answers.padKeys(with: plan.replacement).filter { $0.ledger == .treatment }
        #expect(treatment.map(\.form) == [.lozenge])
    }

    @Test("each ledger is numbered from zero, independently of the other")
    func positionsAreWithinALedger() {
        // The column is ordered within a ledger — the index is
        // `(user_id, ledger, position)` — because the pad draws two groups.
        // Numbering straight through would sort the treatment keys after a
        // gap whose size depends on how many things somebody is quitting.
        let answers = answers(sources: [.pouches, .cigarettes], treatments: [.patch, .lozenge])
        let keys = answers.padKeys(with: plan(for: answers).replacement)

        #expect(keys.filter { $0.ledger == .source }.map(\.position) == [0, 1])
        #expect(keys.filter { $0.ledger == .treatment }.map(\.position) == [0, 1])
    }
}

/// Covers the one invariant the type is shaped to make unfalsifiable.
struct PadFormTests {
    @Test("every form sits in the ledger the table's own constraint puts it in")
    func theLedgerSplitMatchesTheSchema() {
        // Restated from `pad_keys_form_matches_ledger` deliberately. A case
        // added to the wrong side here would build, and the failure would be
        // an insert rejected by Postgres on a user's phone — the one place the
        // check cannot be read.
        let treatment: Set<PadForm> = [.patch, .lozenge, .gum, .inhaler, .spray]
        let source: Set<PadForm> = [.pouch, .vape, .cigarette, .dip, .other]

        #expect(treatment.union(source) == Set(PadForm.allCases), "a form belongs to neither list")
        #expect(treatment.isDisjoint(with: source))
        #expect(treatment.allSatisfy { $0.ledger == .treatment })
        #expect(source.allSatisfy { $0.ledger == .source })
    }

    @Test("the wire values are the strings the column stores")
    func theRawValuesAreTheSchemas() {
        // Spelled out rather than trusted to the case names, because the
        // column is `text` with a check: a rename that looks cosmetic in Swift
        // is a constraint violation on the wire.
        #expect(PadForm.allCases.map(\.rawValue) == [
            "patch", "lozenge", "gum", "inhaler", "spray",
            "pouch", "vape", "cigarette", "dip", "other",
        ])
        #expect(PadKey.Ledger.treatment.rawValue == "treatment")
        #expect(PadKey.Ledger.source.rawValue == "source")
    }
}
