import SwiftUI

/// The onboarding sequence, in order.
///
/// Declared whole rather than grown a case at a time, because the progress
/// indicator needs to know how far through the run a screen sits — and a
/// sequence that only lists what has been built would report the last finished
/// screen as the end.
enum OnboardingStep: Int, CaseIterable, Hashable {
    case whatYouUse, strength, amount, firstUse
    case sickInBed, treatment, startingLine, triggers
    case triedBefore, readiness, quitDate, planPreview

    /// Four steps to a section. Three sections of four move visibly, where
    /// twelve ticks on one track read as barely moving.
    var progress: OnboardingProgress {
        let perSection = OnboardingStep.allCases.count / OnboardingProgress.sections
        return OnboardingProgress(
            section: rawValue / perSection,
            sectionCount: OnboardingProgress.sections,
            fraction: Double(rawValue % perSection + 1) / Double(perSection)
        )
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

/// Drives the run and owns the answers.
///
/// A `NavigationStack` over a path rather than a switch on one index, so back
/// works the way the platform's does — including the edge swipe — without the
/// flow having to model a history of its own.
struct OnboardingFlow: View {
    /// Called when the run is over. Required rather than optional: the last
    /// screen's CTA has to go somewhere, and a default of "do nothing" would
    /// make a finished run indistinguishable from a broken button.
    let onFinish: (CompletedRun) -> Void
    /// Passed through to the last screen. The run does not own the write, but
    /// it owns the screen that reports it.
    var status: PlanStatus = .absent

    @State private var answers = OnboardingAnswers()
    @State private var path: [OnboardingStep] = []

    var body: some View {
        NavigationStack(path: $path) {
            screen(for: .whatYouUse)
                .navigationBarBackButtonHidden()
                .navigationDestination(for: OnboardingStep.self) { step in
                    screen(for: step).navigationBarBackButtonHidden()
                }
        }
    }

    @ViewBuilder
    private func screen(for step: OnboardingStep) -> some View {
        switch step {
        case .whatYouUse:
            WhatYouUseView(answers: answers) { advance(from: step) }
        case .strength:
            StrengthView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .amount:
            AmountView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .firstUse:
            FirstUseView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .sickInBed:
            SickInBedView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .treatment:
            TreatmentView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .startingLine:
            // No back closure: the screen has nothing to change, and every
            // figure on it comes from an answer given earlier.
            if let startingLine = answers.startingLine {
                StartingLineView(startingLine: startingLine) { advance(from: step) }
            } else {
                OnboardingPlaceholderView(step: step, onBack: goBack)
            }
        case .triggers:
            TriggersView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .triedBefore:
            TriedBeforeView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .readiness:
            ReadinessView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .quitDate:
            QuitDateView(
                answers: answers,
                onContinue: { advance(from: step) },
                onBack: goBack
            )
        case .planPreview:
            // Same shape as O6: the screen renders a value or it does not
            // render. Every figure on it is derived, so there is nothing to
            // show for a run that cannot produce a plan.
            if let preview = answers.planPreview {
                PlanPreviewView(
                    preview: preview,
                    status: status,
                    // The draft is built from the preview on screen rather than
                    // from the answers again, so the row cannot disagree with
                    // what the user just agreed to.
                    onContinue: { answers.completedRun(shown: preview).map(onFinish) },
                    onBack: goBack
                )
            } else {
                OnboardingPlaceholderView(step: step, onBack: goBack)
            }
        }
        // No `default`. Every step is built, so the switch is exhaustive — and
        // leaving it exhaustive means a step added later fails to compile
        // rather than quietly landing on a placeholder nobody notices.
    }

    private func advance(from step: OnboardingStep) {
        guard var next = step.next else { return }
        // Skip questions this run cannot answer rather than showing them empty.
        while !applies(next), let following = next.next { next = following }
        path.append(next)
    }

    /// Whether a step has anything to ask, given what the user has said.
    /// Lives on the answers, not here, so a skip can be asserted in a test —
    /// a screen the run silently walks past is invisible from the outside.
    private func applies(_ step: OnboardingStep) -> Bool {
        answers.shouldAsk(step)
    }

    private func goBack() {
        _ = path.popLast()
    }
}

/// Stands in for a screen that cannot render.
///
/// No longer covers unbuilt steps — every step exists now. What remains is the
/// two screens that show a derived value: if the run somehow reaches one
/// without the answers behind it, this says so rather than drawing a plan out
/// of nothing.
///
/// Deliberately says so on screen, and says what to do about it. The
/// alternative — an enabled Continue that does nothing — is indistinguishable
/// from a bug to anyone driving the app, including whoever is reviewing the
/// screen before it.
///
/// The copy names no step. It used to print the case name, which was fair when
/// this stood in for work not yet done and is debug output now that it stands
/// in for a missing answer.
struct OnboardingPlaceholderView: View {
    let step: OnboardingStep
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Your plan",
            progress: step.progress,
            question: "Something's missing.",
            helper: """
            This screen is built from answers you gave earlier, and one of them didn't reach it. \
            Go back a step and it'll fill in.
            """,
            cta: "Back",
            onContinue: onBack,
            onBack: onBack
        ) {
            EmptyView()
        }
    }
}
