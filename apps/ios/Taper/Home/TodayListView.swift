import SwiftUI

/// L7 — the day as a list: every check-in on it, in the order it was logged.
///
/// Pushed from home's tracking card rather than given a tab, which is how the
/// board reaches it: the back button reads "Home" and the tab bar stays put
/// with home still selected. That is the whole reason this is a push and not a
/// sheet — a list of what you have logged is a place you go, not a moment you
/// dismiss, and somebody who corrects a mis-tap here usually wants the pad next.
///
/// Today only, for now. The board draws yesterday and the days before it
/// underneath, each collapsed to a summary and a meter against *that day's*
/// cap, and that needs a range read and a per-day ceiling the store cannot
/// answer yet.
struct TodayListView: View {
    let status: DayStatus
    let entries: [StoredCheckIn]
    /// The day's ceiling, for the line under the title.
    let summary: String
    let onBack: () -> Void
    /// Opens one entry. The rows were drawn before there was anywhere for them
    /// to go, which is why this arrives after the list rather than with it.
    let onSelect: (StoredCheckIn) -> Void
    /// Yesterday, when it has been read. Nil while it is still loading or when
    /// it could not be — an absent section says less wrongly than an empty one.
    var yesterday: DayRollup?
    /// Set when yesterday could not be read. Drawn as a line rather than left
    /// out, because a section that silently vanishes reads as an app losing
    /// track of days rather than as a request that failed.
    var isYesterdayUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pinned. It is the way out, and a day long enough to scroll is
            // exactly the day you do not want to scroll back up to leave.
            back.padding(.horizontal, AppLayout.gutter)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, AppSpacing.l)

                    switch status {
                    case .loading:
                        loading.padding(.top, AppSpacing.xxl)
                    case .ready where entries.isEmpty:
                        empty.padding(.top, AppSpacing.l)
                    case .ready:
                        rows.padding(.top, AppSpacing.sm)
                    case let .unavailable(message):
                        note(message).padding(.top, AppSpacing.l)
                    }

                    if let yesterday {
                        yesterdaySection(yesterday).padding(.top, AppSpacing.xxl)
                    } else if isYesterdayUnavailable {
                        Text("Couldn't load yesterday.")
                            .font(AppFont.text(AppSize.caption))
                            .foregroundStyle(AppColor.cautionInk)
                            .padding(.top, AppSpacing.xxl)
                    }

                    unbuilt.padding(.top, AppSpacing.xxl)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppLayout.gutter)
            }
            // A heavy day runs past the bottom of the screen — twenty check-ins
            // is a bad day, not an impossible one, and without this the oldest
            // of them cannot be reached at all.
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, AppSpacing.smPlus)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    // The two branches worth checking without a layout pass. A screen whose
    // states can only be told apart by rendering it is a screen whose states
    // are not checked.

    /// A day that read cleanly and has nothing on it.
    ///
    /// Never true of a day still loading or one that failed — those have their
    /// own sentence, because "nothing logged today yet" over a day the app
    /// could not see is what invites a second dose.
    var isEmptyDay: Bool {
        status == .ready && entries.isEmpty
    }

    /// The count and total, and only when the day is known.
    ///
    /// `TodayRecord` keeps the last day's entries through a reload and through
    /// a failed read, so this sentence can describe a real day while the body
    /// below it is a spinner or an apology. Dropped rather than dashed: it is
    /// a sentence, not a figure, and half of one reads worse than none.
    ///
    /// The same rule the card's bar follows, and for the same reason — a
    /// screen that answers with stale numbers while saying it does not know is
    /// giving two answers to one question.
    var summaryText: String? {
        status == .ready ? summary : nil
    }

    /// Why the day is not shown, when there is a reason to give.
    var failureText: String? {
        guard case let .unavailable(message) = status else { return nil }
        return message
    }

    private var back: some View {
        BackControl(destination: "Home", action: onBack)
            .accessibilityIdentifier("today.back")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Today")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)
            if let summaryText {
                Text(summaryText)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(entries, id: \.id) { entry in
                let row = CheckInListRow(entry: entry)
                // The accessibility lives on the button, not inside it. A row
                // that declares itself a leaf and is then wrapped in a button
                // gives VoiceOver something it can find and cannot activate —
                // and a tap lands on a container that does nothing. The pad's
                // keys are built the same way for the same reason.
                Button { onSelect(entry) } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.spokenText)
                    .accessibilityIdentifier("today.row.\(entry.id)")
            }
        }
    }

    /// A day with nothing on it, which is how every day starts.
    ///
    /// Never the same sentence as a failed read. "Nothing logged yet" over a
    /// day the app could not see is what invites a second dose.
    private var empty: some View {
        Text("Nothing logged today yet.")
            .font(AppFont.text(AppSize.body))
            .foregroundStyle(AppColor.inkMuted)
    }

    private var loading: some View {
        HStack(spacing: AppSpacing.m) {
            ProgressView().tint(AppColor.ink)
            Text("Loading today…")
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    private func note(_ message: String) -> some View {
        Text(message)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.cautionInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.m)
            .background(AppColor.cautionSurface, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    /// Says what is missing, as every unfinished surface here does.
    /// Yesterday, collapsed to what it came to and the ceiling it came to it
    /// against.
    ///
    /// Its own cap, not today's. That is the whole reason the plan is versioned:
    /// a day is a fact about the plan in force on it, and measuring last Tuesday
    /// against this Tuesday's ceiling would restate it every time the taper
    /// steps down.
    private func yesterdaySection(_ day: DayRollup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.smPlus) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text("Yesterday")
                        .font(AppFont.display(AppSize.unit))
                        .foregroundStyle(AppColor.ink)
                    Text(day.countText)
                        .font(AppFont.text(AppSize.caption))
                        .foregroundStyle(AppColor.inkMuted)
                }
                Spacer(minLength: AppSpacing.sm)
                Text(day.totalText)
                    .font(AppFont.text(AppSize.caption, .medium))
                    .foregroundStyle(day.isOver ? AppColor.over : AppColor.inkMuted)
            }

            miniTrack(day)

            Text(day.summarySentence)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yesterday, \(day.countText), \(day.totalText). \(day.summarySentence)")
    }

    /// A 6pt bar, and only ever one segment of it.
    ///
    /// Today's meter has three because today has a tap in progress. Yesterday
    /// has none — it is finished — so the bar fills and the colour says whether
    /// it went over, rather than a tail running past the end.
    private func miniTrack(_ day: DayRollup) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(day.isOver ? AppColor.over : AppColor.accent)
                .frame(width: proxy.size.width * day.fraction)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 6)
        .background(AppColor.sunken, in: Capsule())
        .clipShape(Capsule())
    }

    private var unbuilt: some View {
        Text("""
        The days before yesterday belong here too, and aren't built yet.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One check-in, as the board draws it: a tilted mark, what it was, what it cost.
///
/// The tile leans and the mark inside it does not — the opposite of the pad,
/// where the mark leans inside a square key. `NicotineMark` holds the shape and
/// each surface supplies its own angle, which is why the pouch is not tilted
/// twice here.
struct CheckInListRow: View {
    let entry: StoredCheckIn

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            tile
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(labelText)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(entry.detailText)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(figureText)
                .font(AppFont.display(AppSize.unitSmall))
                .foregroundStyle(AppColor.ink)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, AppSpacing.mPlus)
        .overlay(alignment: .bottom) { Rectangle().fill(AppColor.line).frame(height: 1) }
        // The whole row, not the ink on it. A plain button takes hits only
        // where its content is opaque, and the middle of this one is the gap
        // between two lines of text — so without this the row reports itself
        // hittable and swallows the tap.
        .contentShape(Rectangle())
    }

    /// The quantity rides in the label rather than in the figure.
    ///
    /// The figure is what the day was charged — two 3 mg pouches is 6 mg
    /// against the cap, and printing "3 mg" beside a row worth 6 would make the
    /// column stop adding up to the total in the header above it.
    ///
    /// A single tap is not counted at anyone: "Pouch × 1" is noise on the
    /// common case.
    var labelText: String {
        entry.quantity > 1 ? "\(entry.label) × \(entry.quantity)" : entry.label
    }

    /// What the day was charged for this row.
    var figureText: String { "\(entry.totalMg.clean) mg" }

    /// The row read out, in the order the eye takes it: what, which kind, how
    /// much, when.
    ///
    /// The form is spoken because it is the one word that says whether the row
    /// counts against the cap — "Nicorette ice mint" does not tell you that and
    /// "Gum" does. Leaving it to the sighted row only would make the listened
    /// version the poorer of the two on exactly the fact it exists to carry.
    ///
    /// Dropped when the label already is the form. The board's own first row is
    /// "Pouch" filed under `.pouch`, which reads fine at two sizes on screen
    /// and as a stutter out loud.
    var spokenText: String {
        var parts = [labelText]
        if entry.label.caseInsensitiveCompare(entry.form.label) != .orderedSame {
            parts.append(entry.form.label)
        }
        parts.append("\(entry.totalMg.clean) milligrams")
        parts.append(entry.timeText)
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var tile: some View {
        if NicotineMark.isDrawn(entry.form) {
            NicotineMark(form: entry.form, side: 22)
                .frame(width: 40, height: 40)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.small))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .strokeBorder(AppColor.line, lineWidth: 1)
                }
                .rotationEffect(.degrees(-4))
        } else {
            // The forms with no mark still need the lane, or the labels beside
            // them step left and the rows stop sharing a column.
            Color.clear.frame(width: 40, height: 40)
        }
    }
}
