import SwiftUI

/// L2's tracking card: what today has come to, and the two ways out of it.
///
/// The first place home says anything about the *day* rather than the plan.
/// Every other figure on that screen comes off the taper and is known at
/// launch; this one needs a request, so the card carries its own waiting and
/// failure states rather than holding the screen up. The cap tile above it
/// still draws instantly.
///
/// One action for now. The board draws a second — "See check-in history",
/// a text button under this one — and it lands with L7, the screen it opens. A
/// control that leads nowhere is worse than an absent one, and this card is the
/// only door that screen will have.
struct TodaySoFarCard: View {
    let status: DayStatus
    let tally: TodaysTally
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            header
            DayTrack(tally: trackTally, context: .summary)
            if let failureText { note(failureText) }
            checkInButton
        }
        .padding(AppSpacing.xl)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
    }

    /// "Today so far" against the figure it came to.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today so far")
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.ink)

            Spacer(minLength: AppSpacing.sm)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(figureText)
                    .font(AppFont.display(AppSize.heading))
                    .foregroundStyle(isOverToday ? AppColor.over : AppColor.ink)
                Text("of \(tally.ceilingMg.clean) mg")
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenTotalText)
    }

    // What the card says, kept as plain values rather than buried in the body.
    // A view whose decisions can only be seen by rendering it is a view whose
    // decisions are not checked.

    /// An em dash until the day is known.
    ///
    /// Not "0". A day that has not loaded and a day with nothing on it are
    /// different facts, and showing a zero for the first is the app asserting
    /// something it has not been told — the same distinction `DayStatus` draws
    /// between `ready` and `unavailable`.
    var figureText: String {
        status == .ready ? tally.loggedMg.clean : "—"
    }

    /// The day the bar draws, which is nothing at all until the day is known.
    ///
    /// `TodayRecord` keeps the last day's entries through a reload and through
    /// a failed read, so the tally handed to this card can describe a real day
    /// while the status says otherwise. Drawing it would put a filled bar under
    /// an em dash — the figure saying it does not know and the bar answering
    /// anyway, which is the two-answers-to-one-question this card was built to
    /// avoid.
    ///
    /// Emptied rather than hidden. The card keeps its height either way, and a
    /// surface that changes size while a request lands is one that moves the
    /// button out from under a thumb. The ceiling is kept so the empty track is
    /// still the right bar for the day it is about.
    var trackTally: TodaysTally {
        guard status == .ready else {
            return TodaysTally(entries: [], pending: nil, ceilingMg: tally.ceilingMg)
        }
        return tally
    }

    /// Whether today's figure should be marked as over the cap.
    ///
    /// Only a day that read cleanly can be over one. A dash is not a number,
    /// and colouring it red would report a breach out of a failed request.
    var isOverToday: Bool { status == .ready && tally.isOver }

    /// The reason the figure is a dash, when there is one to give.
    var failureText: String? {
        guard case let .unavailable(message) = status else { return nil }
        return message
    }

    /// Says the over-cap state as well as the numbers.
    ///
    /// The figure turns red and the bar grows a red tail, and neither of those
    /// reaches somebody using VoiceOver — who would hear "14 of 12 milligrams"
    /// and be left to do the comparison themselves. The one state this card
    /// marks in colour has to be said in words too.
    var spokenTotalText: String {
        guard status == .ready else { return "Today so far, not loaded yet" }
        let total = "Today so far, \(tally.loggedMg.clean) of \(tally.ceilingMg.clean) milligrams"
        return isOverToday ? "\(total), over today's cap" : total
    }

    /// Why the figure is a dash.
    ///
    /// Said rather than left blank: a card showing "—" with no explanation
    /// reads as a day with nothing on it, which is the one reading that would
    /// invite somebody to log against a day the app could not see.
    private func note(_ message: String) -> some View {
        Text(message)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.cautionInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var checkInButton: some View {
        Button(action: onCheckIn) {
            HStack(spacing: AppSpacing.sm) {
                PlusMark()
                Text("Check in on the pad")
                    .font(AppFont.text(AppSize.body, .medium))
            }
            .foregroundStyle(AppColor.inkInverse)
            .frame(maxWidth: .infinity)
            .frame(height: AppLayout.action)
            .background(AppColor.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.checkIn")
    }
}

/// The plus on the check-in button, on the board's 16-unit grid.
///
/// Drawn rather than an SF Symbol, for the reason the tab marks are: one stroke
/// at one weight, which the system set is not.
private struct PlusMark: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 16, y: size.height / 16)
            var path = Path()
            path.move(to: CGPoint(x: 8, y: 3))
            path.addLine(to: CGPoint(x: 8, y: 13))
            path.move(to: CGPoint(x: 3, y: 8))
            path.addLine(to: CGPoint(x: 13, y: 8))
            context.stroke(
                path,
                with: .style(.foreground),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )
        }
        .frame(width: 16, height: 16)
    }
}
