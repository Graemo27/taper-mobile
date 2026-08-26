import SwiftUI

/// L6 — the moment after logging, on a full accent field: "Logged.", the
/// day's meter, and one way out.
///
/// The one celebratory surface in the app, and the celebration is a fact: the
/// figure, the bar, and a sentence that ends "— or don't", because a
/// confirmation that demands to see you again is a streak mechanic wearing a
/// kind voice. Over the cap the sentence changes to the app's whole position
/// in one line: noted, not judged, and tomorrow's cap still drops.
struct LoggedView: View {
    /// The day as it stands with the new row folded in.
    let tally: TodaysTally
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            Text("Logged.")
                .font(AppFont.display(AppSize.figure))
                .foregroundStyle(AppColor.ink)

            meter.padding(.top, AppSpacing.lPlus)

            Text(sentence)
                .font(AppFont.text(AppSize.bodyLarge))
                .lineSpacing(AppLeading.relaxed - AppSize.bodyLarge)
                .foregroundStyle(AppColor.onAccentMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.lPlus)

            Spacer(minLength: 0)

            doneButton
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.bottom, AppSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(AppColor.accent)
    }

    private var meter: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.trackOnTile)
                    Capsule()
                        .fill(fillColor)
                        .frame(width: max(16, proxy.size.width * fillFraction))
                }
            }
            .frame(height: 16)

            HStack {
                Text(figureText)
                    .font(AppFont.text(AppSize.body, .medium))
                    .foregroundStyle(AppColor.ink)
                Spacer(minLength: AppSpacing.sm)
                Text(remainderText)
                    .font(AppFont.text(AppSize.body))
                    .foregroundStyle(AppColor.onAccentMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(figureText), \(remainderText)")
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("logged.done")
    }

    // What the screen says, as plain values.

    /// "10.5 of 12 mg today" — sources only, the same figure home reads.
    var figureText: String {
        "\(tally.loggedMg.clean) of \(tally.ceilingMg.clean) mg today"
    }

    /// "1.5 mg left", or how far over — the remainder is the useful number on
    /// this screen, because the next decision is about what is left.
    var remainderText: String {
        tally.isOver
            ? "\(tally.overByMg.clean) mg over"
            : "\((tally.ceilingMg - tally.loggedMg).clean) mg left"
    }

    /// The bar is ink until the day is over, and the overflow colour after —
    /// the same two answers the tracking card gives.
    var fillColor: Color { tally.isOver ? AppColor.over : AppColor.ink }

    /// Clamped full rather than overflowing: a past-tense meter reports, and
    /// the words beside it carry the size of the breach.
    var fillFraction: Double {
        guard tally.ceilingMg > 0 else { return tally.loggedMg > 0 ? 1 : 0 }
        return min(1, tally.loggedMg / tally.ceilingMg)
    }

    /// Under: the board's sentence, "— or don't" included. Over: the position
    /// the over-cap note wrote, minus the "Logged." this screen already says.
    var sentence: String {
        tally.isOver
            ? "You're \(tally.overByMg.clean) mg over — noted, not judged. Tomorrow's cap still drops."
            : "Still under today's cap. See you at the next craving — or don't."
    }
}
