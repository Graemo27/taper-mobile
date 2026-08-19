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
        default:
            // Explicit rather than silent. An unbuilt step used to be an empty
            // closure on an enabled button, which left the run looking broken
            // instead of unfinished.
            OnboardingPlaceholderView(step: step, onBack: goBack)
        }
    }

    private func advance(from step: OnboardingStep) {
        guard let next = step.next else { return }
        path.append(next)
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
