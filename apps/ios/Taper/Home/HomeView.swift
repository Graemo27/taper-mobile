import SwiftUI

/// L1 — where the app opens once there is a plan: the day, the countdown and
/// today's cap.
///
/// Deliberately a subset of the board, because the craving prompt, the check-in
/// and the tracking card each need a screen or a table that does not exist yet,
/// and a control that cannot do its job is worse than an absent one.
struct HomeView: View {
    let progress: PlanProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayPill
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.smPlus)

            tiles.padding(.top, AppSpacing.xxl)
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

            // The board fills a bar with what has been used today. Nothing is
            // logged yet, so there is no figure to fill it with — and a bar
            // drawn empty would say the day is untouched, which the app has no
            // way to know.
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

    /// Says what is missing, for the same reason every other unfinished surface
    /// in this app does: a screen that quietly lacks its main action reads as
    /// broken, and one that says so reads as early.
    private var unbuilt: some View {
        Text("""
        Logging is the next thing to build. Your cap and your dates are on the server — there's \
        just nowhere to record against them yet.
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
    )!)
}
