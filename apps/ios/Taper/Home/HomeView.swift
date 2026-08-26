import SwiftUI

/// L1 — where the app opens once there is a plan: the day, the countdown and
/// today's cap.
///
/// Deliberately a subset of the board, because the daily check-in needs a table
/// that does not exist yet, and a control that cannot do its job is worse than
/// an absent one.
struct HomeView: View {
    let progress: PlanProgress
    /// Today, for the tracking card. Passed rather than made here, because the
    /// pad holds the same record and two of them would be two answers about one
    /// day.
    @Bindable var today: TodayRecord
    /// The pad, for the card's per-key breakdown. Nil while unknown, and the
    /// card draws no row rather than a row of zeros.
    let pad: Pad?
    /// Switches to the log tab. Home does not own the selection, so the card's
    /// button reports the intent and lets the bar act on it.
    let onCheckIn: () -> Void
    /// Opens today as a list. Home does not own the navigation stack either.
    let onSeeHistory: () -> Void
    /// Opens L8. Above the countdown and the cap on the board, and that order
    /// is the product: somebody who opens this app mid-craving should not have
    /// to read a progress figure before reaching the one screen that helps.
    let onCraving: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayPill
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.smPlus)

            cravingHero.padding(.top, AppSpacing.xxl)
            tiles.padding(.top, AppSpacing.xl)
            tracking.padding(.top, AppSpacing.xxl)
            unbuilt.padding(.top, AppSpacing.xxl)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    /// The board's first thing on the screen: what it is for, and the way in.
    ///
    /// The heading is a claim, not a question — "it will crest and pass" is the
    /// one fact this app has that a person mid-craving does not, and putting it
    /// on home means they have read it before they ever tap.
    private var cravingHero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("RIGHT NOW")
                .font(AppFont.text(AppSize.micro, .medium))
                .tracking(AppTracking.eyebrowWide(AppSize.micro))
                .foregroundStyle(AppColor.inkMuted)
            Text("Craving? It will crest and pass.")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onCraving) {
                HStack(spacing: AppSpacing.smPlus) {
                    CrestMark()
                    Text("I'm craving right now")
                        .font(AppFont.text(AppSize.bodyLarge, .medium))
                }
                .foregroundStyle(AppColor.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.craving")
        }
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
                tally: today.loggedTally(ceilingMg: progress.todaysCapMg),
                breakdown: pad.map { DayBreakdown(pad: $0, entries: today.entries) },
                outlastedCount: today.entries.filter(\.isUrge).count,
                onCheckIn: onCheckIn,
                onSeeHistory: onSeeHistory
            )
        }
    }

    /// Says what is missing, for the same reason every other unfinished surface
    /// in this app does: a screen that quietly lacks its main action reads as
    /// broken, and one that says so reads as early.
    ///
    /// Rewritten twice now — when the log tab landed, and again when the
    /// craving prompt above it did. Each time it named something that had
    /// stopped being missing, and a note about what is missing is worth nothing
    /// once it is quietly wrong.
    private var unbuilt: some View {
        Text("""
        The daily check-in still belongs here, and nicotine over time — the week against the \
        stepping cap — goes below the card.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The wave on the craving button: one crest, falling.
///
/// Drawn rather than borrowed from SF Symbols, for `NicotineMark`'s reason: the
/// board's mark is an exact stroke on an exact grid, and the nearest system
/// glyph is a different shape wearing the same idea.
private struct CrestMark: View {
    /// The board's grid, and its stroke.
    private static let grid: CGFloat = 20
    private static let stroke: CGFloat = 1.8

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / Self.grid, y: size.height / Self.grid)
            context.stroke(
                Self.wave,
                with: .color(AppColor.onAccent),
                style: StrokeStyle(lineWidth: Self.stroke, lineCap: .round)
            )
        }
        .frame(width: Self.grid, height: Self.grid)
        .accessibilityHidden(true)
    }

    private static var wave: Path {
        var path = Path()
        path.move(to: CGPoint(x: 2, y: 13))
        path.addCurve(to: CGPoint(x: 7, y: 7),
                      control1: CGPoint(x: 4.5, y: 13), control2: CGPoint(x: 4.5, y: 7))
        path.addCurve(to: CGPoint(x: 12, y: 13),
                      control1: CGPoint(x: 9.5, y: 7), control2: CGPoint(x: 9.5, y: 13))
        path.addCurve(to: CGPoint(x: 18, y: 7),
                      control1: CGPoint(x: 14.5, y: 13), control2: CGPoint(x: 14.5, y: 7))
        return path
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
    )!, today: TodayRecord(store: nil), pad: nil, onCheckIn: {}, onSeeHistory: {}, onCraving: {})
}
