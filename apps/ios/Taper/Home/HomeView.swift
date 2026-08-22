import SwiftUI

/// L1 — where the app opens once there is a plan: the day, the countdown and
/// today's cap.
///
/// Deliberately a subset of the board, because the craving prompt and the daily
/// check-in each need a screen or a table that does not exist yet, and a control
/// that cannot do its job is worse than an absent one.
struct HomeView: View {
    let progress: PlanProgress
    /// Today, for the tracking card. Passed rather than made here, because the
    /// pad holds the same record and two of them would be two answers about one
    /// day.
    @Bindable var today: TodayRecord
    /// Switches to the log tab. Home does not own the selection, so the card's
    /// button reports the intent and lets the bar act on it.
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayPill
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.smPlus)

            tiles.padding(.top, AppSpacing.xxl)
            tracking.padding(.top, AppSpacing.xxl)
            unbuilt.padding(.top, AppSpacing.xxl)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    /// "Day 12 of 60", or just the day for a run with no end in sight.
    private var dayPill: some View {
        Text(dayText)
            .font(AppFont.text(AppSize.caption, .medium))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, AppSpacing.mPlus)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColor.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(AppColor.line, lineWidth: 1) }
    }

    private var dayText: String {
        guard let total = progress.totalDays else { return "Day \(progress.day)" }
        return "Day \(progress.day) of \(total)"
    }

    /// The countdown and the cap, side by side — or the cap alone.
    ///
    /// A run holding where it is gets one full-width tile rather than a second
    /// one with a dash in it. There is no number to put there: that user
    /// declined to name a date, and drawing an empty countdown would be the
    /// screen asking again.
    private var tiles: some View {
        HStack(spacing: AppSpacing.m) {
            if let days = progress.daysUntilQuitDate {
                countdownTile(days)
            }
            capTile
        }
    }

    private func countdownTile(_ days: Int) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text("\(days)")
                .font(AppFont.display(AppSize.hero))
                .foregroundStyle(AppColor.ink)
            Text("days until\nquit date")
                .font(AppFont.text(AppSize.label, .medium))
                .multilineTextAlignment(.center)
                .lineSpacing(19 - AppSize.label)
                .foregroundStyle(AppColor.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: AppLayout.tile)
        .background(AppColor.accent, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "1 day until your quit date" : "\(days) days until your quit date")
    }

    private var capTile: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("today's cap")
                .font(AppFont.text(AppSize.caption, .medium))
                .foregroundStyle(AppColor.onSecondary)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(progress.todaysCapMg.clean)
                    .font(AppFont.display(AppSize.metric))
                Text("mg")
                    .font(AppFont.display(AppSize.unitSmall))
            }
            .foregroundStyle(AppColor.onSecondary)

            // The board fills a bar here with what has been used today. That
            // now lives in the tracking card below, which is where the board
            // puts the day — this tile stays the plan's number alone, so it can
            // still be drawn before any request comes back.
            if let next = progress.nextStep {
                Text("drops to \(next.capMg.clean) \(next.whenPhrase)")
                    .font(AppFont.text(AppSize.micro))
                    .lineSpacing(AppLeading.tight - AppSize.micro)
                    .foregroundStyle(AppColor.onSecondaryMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: AppLayout.tile)
        .padding(.horizontal, AppSpacing.lPlus)
        .background(AppColor.secondary, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
        .accessibilityElement(children: .combine)
    }

    /// L2's tracking section: the eyebrow, then the card.
    ///
    /// The one figure on this screen that needs a request. It is read here
    /// rather than on the log tab alone because the card is home's — but the
    /// tiles above do not wait for it, so somebody who only wants their cap
    /// still gets it at launch.
    private var tracking: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Nicotine tracking")
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            TodaySoFarCard(
                status: today.status,
                tally: today.tally(ceilingMg: progress.todaysCapMg),
                onCheckIn: onCheckIn
            )
        }
    }

    /// Says what is missing, for the same reason every other unfinished surface
    /// in this app does: a screen that quietly lacks its main action reads as
    /// broken, and one that says so reads as early.
    ///
    /// Rewritten when the log tab landed. It used to say logging was the next
    /// thing to build, which stopped being true the moment there was a way to
    /// reach it — and a note about what is missing is worth nothing once it is
    /// quietly wrong.
    private var unbuilt: some View {
        Text("""
        The craving prompt and the daily check-in still belong here, and the card above will \
        grow a breakdown and a link to the full list.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    HomeView(progress: PlanProgress(
        plan: StoredTaperPlan(
            id: 1,
            startingCapMg: 18,
            currentCapMg: 12,
            capEffectiveFrom: PlanDay.wireFormat(Date().addingTimeInterval(-11 * 86_400)),
            quitDate: PlanDay.wireFormat(Date().addingTimeInterval(48 * 86_400)),
            firstUseMinutes: 20,
            sickInBed: true
        ),
        today: Date()
    )!, today: TodayRecord(store: nil), onCheckIn: {})
}
