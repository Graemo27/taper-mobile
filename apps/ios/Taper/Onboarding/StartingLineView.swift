import SwiftUI

/// O6 — the run said back, before the questions resume.
///
/// The only screen in onboarding with no question, no progress bar and no way
/// back, and the only one that fills with the accent. All three are the same
/// decision: this is a beat rather than a step, and the number on it is the one
/// every later screen is measured against.
///
/// There is no back chevron because there is nothing here to change — every
/// figure comes from an answer given earlier, and the way to correct one is to
/// correct the answer.
struct StartingLineView: View {
    let startingLine: StartingLine
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: AppSpacing.lPlus) {
                Text(startingLine.headline)
                    .font(AppFont.display(AppSize.statement))
                    .lineSpacing(AppLeading.statement - AppSize.statement)
                    .foregroundStyle(AppColor.onAccent)

                Text(startingLine.body)
                    .font(AppFont.text(AppSize.body))
                    .lineSpacing(AppLeading.relaxed - AppSize.body)
                    .foregroundStyle(AppColor.onAccent)

                Squiggle()
                    .stroke(AppColor.onAccent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 220, height: 64)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppLayout.gutter)

            Spacer(minLength: 0)

            OnboardingCTA(title: "Build my plan", action: onContinue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.accent)
    }
}

/// The wandering line under the copy.
///
/// Not a chart. It rises and falls and ends slightly below where it began,
/// because a straight descent is a promise the plan does not make — the
/// evidence for a taper is weak, and the shape here should not imply a
/// tidiness the product cannot deliver.
private struct Squiggle: Shape {
    func path(in rect: CGRect) -> Path {
        // Points from the Paper board, expressed against its 220 × 64 box so
        // the curve keeps its proportions at any size.
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 220, y: rect.minY + rect.height * y / 64)
        }

        var path = Path()
        path.move(to: point(6, 14))
        path.addCurve(to: point(60, 50), control1: point(36, 14), control2: point(30, 50))
        path.addCurve(to: point(118, 30), control1: point(90, 50), control2: point(96, 22))
        path.addCurve(to: point(178, 44), control1: point(140, 38), control2: point(160, 54))
        path.addCurve(to: point(214, 22), control1: point(196, 34), control2: point(206, 20))
        return path
    }
}

#Preview {
    let answers = OnboardingAnswers()
    answers.toggle(.pouches)
    answers.strengths[.pouches] = StrengthOption.pouch.first { $0.mg == 3 }
    answers.setAmount(6, for: .pouches)
    answers.firstUse = FirstUseOption.all.first { $0.minutes == 20 }
    answers.usesWhenIllInBed = true
    return StartingLineView(startingLine: answers.startingLine!, onContinue: {})
}
