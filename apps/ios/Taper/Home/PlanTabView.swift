import SwiftUI

/// L4 — the whole taper: where it ends, and the descent that gets there.
///
/// Every figure comes off `PlanProgress`, which is the same object the home
/// screen reads its cap from. A second model of one plan is what once put
/// "18 mg — drops to 13.5" on screen in a week when the real next step was 16.
struct PlanTabView: View {
    let progress: PlanProgress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                title
                if let last = progress.lastMilligramDay {
                    lastMilligram(last).padding(.top, AppSpacing.xl)
                }
                descent.padding(.top, AppSpacing.l)
                Text(Self.reassurance)
                    .font(AppFont.text(AppSize.caption))
                    .lineSpacing(AppLeading.snug - AppSize.caption)
                    .foregroundStyle(AppColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.l)
                unbuilt.padding(.top, AppSpacing.xxl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppLayout.gutter)
            .padding(.top, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            // "Your quit plan", not "Jake's". The board names the person and
            // onboarding never asks — twelve questions and not one of them is
            // what to call you. Inventing a name is not an option and demanding
            // one to render a heading is a question asked for the app's benefit
            // rather than the user's.
            Text("Your quit plan")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)
            Text(summary)
                .font(AppFont.text(AppSize.label))
                .lineSpacing(AppLeading.snug - AppSize.label)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "16 mg a day, down to zero." — or where it holds, for a run with no date.
    var summary: String {
        let start = (progress.weeklyCapsMg.first ?? progress.todaysCapMg).clean
        guard progress.weeklyCapsMg.last == 0 else {
            return "\(start) mg a day, holding steady. Your pace is the right pace."
        }
        return "\(start) mg a day, down to zero. Your pace is the right pace."
    }

    /// The end of the descent, and how far off it is.
    private func lastMilligram(_ day: Date) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Last mg")
                    .font(AppFont.text(AppSize.caption, .medium))
                    .foregroundStyle(AppColor.onAccent)
                Text(day.formatted(.dateTime.month(.abbreviated).day()))
                    .font(AppFont.display(AppSize.metric))
                    .foregroundStyle(AppColor.onAccent)
            }
            Spacer(minLength: AppSpacing.m)
            daysBadge
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.accent, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLastMilligram(day))
    }

    func spokenLastMilligram(_ day: Date) -> String {
        let date = day.formatted(.dateTime.month(.wide).day())
        guard let days = progress.daysUntilQuitDate else { return "Last milligram \(date)" }
        return "Last milligram \(date), \(days) \(days == 1 ? "day" : "days") away"
    }

    private var daysBadge: some View {
        VStack(spacing: 0) {
            Text("\(progress.daysUntilQuitDate ?? 0)")
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.onAccent)
            Text("days")
                .font(AppFont.text(AppSize.nano))
                .foregroundStyle(AppColor.onAccentMuted)
        }
        .frame(width: 72, height: 72)
        .background(AppColor.veilOnAccent, in: Circle())
    }

    /// The descent, a week at a time.
    ///
    /// Weeks, not the board's months. The planner steps the ceiling weekly and
    /// nothing in this app computes a monthly figure or a dose interval — the
    /// board's "6–12 doses daily, 1 dose each every 1–2 hours" is guidance from
    /// a source the app does not have. Drawing the schedule it is actually
    /// running is both truthful and more useful.
    private var descent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            dependenceBand
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    weekRow(step: step)
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
    }

    /// Which week of the plan today falls in, counted from its first.
    ///
    /// The schedule starts at the plan's first week, not at this one, so the
    /// top row is only "this week" on the day somebody starts. Taking it from
    /// `progress.day` — the same number home counts its cap from — is what
    /// stops this screen marking an expired ceiling as the one in force.
    var currentWeek: Int { max(0, (progress.day - 1) / 7) }

    /// One row of the descent: the weeks it covers, and the ceiling across them.
    struct Step: Equatable {
        let weeks: ClosedRange<Int>
        let capMg: Double
    }

    /// The descent, collapsed to its distinct figures.
    ///
    /// A slow taper repeats: rounding to the half-milligram turns a long
    /// descent into `9, 8.5, 8.5, 8, 7.5, 7.5…`, and three identical rows read
    /// as a rendering fault rather than a deliberate plateau.
    ///
    /// **The weeks travel with the figure.** Collapsing without them was a bug
    /// on the way here: the row's label came from its position in this list, so
    /// the week after a plateau was named one week early — the list said
    /// "Week 3" for what was actually week four.
    var steps: [Step] {
        var out: [Step] = []
        for (index, cap) in progress.weeklyCapsMg.enumerated() {
            if let last = out.last, last.capMg == cap {
                out[out.count - 1] = Step(weeks: last.weeks.lowerBound...index, capMg: cap)
            } else {
                out.append(Step(weeks: index...index, capMg: cap))
            }
        }
        return out
    }

    private var dependenceBand: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(dependenceText)
                .font(AppFont.text(AppSize.label, .medium))
                .foregroundStyle(AppColor.onAccentTint)
            Text("What the descent below is shaped around.")
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.onAccentTint)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.accentTint, in: RoundedRectangle(cornerRadius: AppRadius.small))
        .accessibilityElement(children: .combine)
    }

    /// The board pairs this with "You are like 11% of Quitters". That figure
    /// has no source in this project and the app states no success rates
    /// anywhere else — `TaperPlan` says so in as many words — so the band names
    /// the dependence and stops.
    var dependenceText: String {
        switch progress.dependence {
        case .low: return "Lower dependence"
        case .moderate: return "Moderate dependence"
        case .high: return "Higher dependence"
        }
    }

    private func weekRow(step: Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            Circle()
                .fill(isCurrent(step) ? AppColor.accent : AppColor.line)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { $0.height - 2 }
            Text(weekLabel(step))
                .font(AppFont.text(AppSize.label, .medium))
                .foregroundStyle(AppColor.ink)
            Spacer(minLength: AppSpacing.sm)
            Text(step.capMg == 0 ? "zero" : "\(step.capMg.clean) mg")
                .font(AppFont.text(AppSize.label))
                .foregroundStyle(AppColor.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// Whether a row is the one in force today.
    func isCurrent(_ step: Step) -> Bool { step.weeks.contains(currentWeek) }

    /// "This week", "Week 4", "Weeks 5–6".
    ///
    /// Numbered from the plan's first week, not from this row's position — a
    /// row after a plateau is further along than the list is long. And "this
    /// week" is the week somebody is actually in, not the top of the list: on a
    /// plan three weeks old the first row is a ceiling that expired a fortnight
    /// ago, and calling it current is how somebody ends up following it.
    func weekLabel(_ step: Step) -> String {
        if isCurrent(step) { return "This week" }
        let first = step.weeks.lowerBound + 1
        let last = step.weeks.upperBound + 1
        return first == last ? "Week \(first)" : "Weeks \(first)–\(last)"
    }

    /// The line under the descent.
    ///
    /// The board reads "FDA-regulated NRT treatments are safe to use as long as
    /// needed". The reassurance is the point and is kept — being slow is not
    /// failing — but the duration half is a claim this project cannot anchor:
    /// the research wiki has notes on NRT's efficacy, dose bands and cardiac
    /// safety, and none on how long it is safe to stay on it.
    ///
    /// So it says what is documented — licensed use, as directed — and sends
    /// the question a label cannot answer to somebody qualified to. The app
    /// states no success rate for the same reason.
    static let reassurance = """
    Your pace is the right pace. Licensed NRT is safe used as directed — if you're on it longer \
    than the label says, a pharmacist can tell you what's right for you.
    """

    /// Says what the board draws here that this cannot yet.
    private var unbuilt: some View {
        Text("""
        Changing your plan belongs here and isn't built yet. Onboarding is still the only way to \
        set one.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }
}
