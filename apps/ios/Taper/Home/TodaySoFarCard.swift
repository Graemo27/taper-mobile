import SwiftUI

/// L2's tracking card: what today has come to, and the two ways out of it.
///
/// The first place home says anything about the *day* rather than the plan.
/// Every other figure on that screen comes off the taper and is known at
/// launch; this one needs a request, so the card carries its own waiting and
/// failure states rather than holding the screen up. The cap tile above it
/// still draws instantly.
///
/// Two actions, deliberately unequal. Logging is what the card is for and gets
/// the filled button; the list is a text button underneath. Two controls of the
/// same weight would ask somebody to choose every time they looked at their own
/// day, and only one of them is the thing this card exists to prompt.
///
/// The second is the *only* door to the list — the board's flows note routes
/// nothing else there — which is why it shipped with the screen it opens rather
/// than before it.
struct TodaySoFarCard: View {
    let status: DayStatus
    let tally: TodaysTally
    /// Today counted per key, or nil while the pad is unknown. Nil and empty
    /// are different facts: an unloaded pad draws no row at all, because a row
    /// of zeros would be the card asserting a day it has not been told about.
    let breakdown: DayBreakdown?
    /// Cravings got through today. Zero draws nothing — the line exists to
    /// make counting one visibly worth doing, not to report its absence.
    let outlastedCount: Int
    let onCheckIn: () -> Void
    /// Opens the day as a list. Reported rather than performed, the same way
    /// `onCheckIn` is: the card owns no more of the navigation than it does of
    /// the tab selection.
    let onSeeHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            header
            DayTrack(tally: trackTally, context: .summary)
            if let shownBreakdown, !shownBreakdown.columns.isEmpty {
                countsRow(shownBreakdown)
            }
            if let outlastedText { outlastedLine(outlastedText) }
            if let failureText { note(failureText) }
            checkInButton
            historyButton
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

    /// The breakdown, only once the day it counts is actually on screen.
    ///
    /// Held back on `trackTally`'s reasoning: the record keeps the last day's
    /// entries through a failed read, so a breakdown could describe a real day
    /// while the figure above says it does not know.
    var shownBreakdown: DayBreakdown? {
        status == .ready ? breakdown : nil
    }

    /// "Also today: 2 cravings outlasted · +0 mg", or nil when there were none
    /// to say — and, like the breakdown, nil until the day is known.
    ///
    /// "+0 mg" is the whole point of the line: it sits under a card of
    /// milligrams saying that the hardest thing done today cost none.
    var outlastedText: String? {
        guard status == .ready, outlastedCount > 0 else { return nil }
        let noun = outlastedCount == 1 ? "craving" : "cravings"
        return "Also today: \(outlastedCount) \(noun) outlasted · +0 mg"
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

    /// The board's counts row, wrapped into runs of three.
    ///
    /// The pad has no key limit, and a single HStack divides its fixed width
    /// by however many keys exist — seven keys would squeeze every word to an
    /// ellipsis. Three per row is the board's own density, and a fourth key
    /// starts a second row inside the same border.
    private func countsRow(_ breakdown: DayBreakdown) -> some View {
        let rows = stride(from: 0, to: breakdown.columns.count, by: 3).map {
            Array(breakdown.columns[$0..<min($0 + 3, breakdown.columns.count)])
        }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                if rowIndex > 0 {
                    Rectangle().fill(AppColor.line).frame(height: 1)
                }
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.element.keyID) { index, column in
                        countColumn(column)
                        if index < row.count - 1 {
                            Rectangle().fill(AppColor.line).frame(width: 1)
                        }
                    }
                }
                .padding(.vertical, AppSpacing.mPlus)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
        .accessibilityIdentifier("home.breakdown")
    }

    private func countColumn(_ column: DayBreakdown.Column) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(column.countText)
                .font(AppFont.display(AppSize.title))
                .foregroundStyle(AppColor.ink)
            Text(column.word)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            Text(column.strengthText)
                .font(AppFont.text(AppSize.nano, .medium))
                .foregroundStyle(column.isUntouched ? AppColor.inkFaint : AppColor.ink)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(column.count) \(column.word), \(column.strengthText) each")
    }

    /// The crest beside the count, the same wave the craving button wears.
    private func outlastedLine(_ text: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            OutlastedMark()
            Text(text)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.outlasted")
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

extension TodaySoFarCard {
    /// The quieter of the two. A text button rather than a second filled one,
    /// because reviewing the day is available, not urged.
    fileprivate var historyButton: some View {
        Button(action: onSeeHistory) {
            HStack(spacing: AppSpacing.s) {
                Text("See check-in history")
                    .font(AppFont.text(AppSize.body, .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppColor.ink)
            .frame(maxWidth: .infinity)
            .frame(height: AppLayout.tap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.seeHistory")
    }
}

/// The double crest beside the outlasted line, on the board's 20-unit grid.
///
/// Drawn rather than an SF Symbol, for `PlusMark`'s reason — and quieter than
/// the button's single crest, because this one reports rather than invites.
private struct OutlastedMark: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 20, y: size.height / 20)
            var path = Path()
            path.move(to: CGPoint(x: 2, y: 13))
            path.addCurve(to: CGPoint(x: 7, y: 7),
                          control1: CGPoint(x: 4.5, y: 13), control2: CGPoint(x: 4.5, y: 7))
            path.addCurve(to: CGPoint(x: 12, y: 13),
                          control1: CGPoint(x: 9.5, y: 7), control2: CGPoint(x: 9.5, y: 13))
            path.addCurve(to: CGPoint(x: 18, y: 7),
                          control1: CGPoint(x: 14.5, y: 13), control2: CGPoint(x: 14.5, y: 7))
            context.stroke(
                path,
                with: .color(AppColor.inkMuted),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
            )
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
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
