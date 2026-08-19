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
        default:
            // Explicit rather than silent. An unbuilt step used to be an empty
            // closure on an enabled button, which left the run looking broken
            // instead of unfinished.
            OnboardingPlaceholderView(step: step, onBack: goBack)
        }
    }

    private func advance(from step: OnboardingStep) {
        guard var next = step.next else { return }
        // Skip questions this run cannot answer rather than showing them empty.
        while !applies(next), let following = next.next { next = following }
        path.append(next)
    }

    /// Whether a step has anything to ask, given what the user has said.
    ///
    /// Only strength branches today: it is a per-piece question, and a run that
    /// names only cigarettes or a vape has no per-piece figure to give. Asking
    /// anyway would make them invent one, and the plan would be built on it.
    private func applies(_ step: OnboardingStep) -> Bool {
        switch step {
        case .strength:
            return answers.sources.contains { $0.usesPerUnitStrength }
        default:
            return true
        }
    }

    private func goBack() {
        _ = path.popLast()
    }
}

/// Stands in for a question that has not been built.
///
/// Deliberately says so on screen. The alternative — an enabled Continue that
/// does nothing — is indistinguishable from a bug to anyone driving the app,
/// including whoever is reviewing the screen before it.
struct OnboardingPlaceholderView: View {
    let step: OnboardingStep
    let onBack: () -> Void

    var body: some View {
        OnboardingScaffold(
            section: "Coming next",
            progress: step.progress,
            question: "Not built yet.",
            helper: "This question — \(String(describing: step)) — is the next change. The run ends here for now.",
            cta: "Back",
            onContinue: onBack,
            onBack: onBack
        ) {
            EmptyView()
        }
    }
}
