import SwiftUI

/// L2's graph card: "Trending down", the bars, and the stepping cap.
///
/// Every claim on it is `Trend`'s; this view only draws. The chart is a Canvas
/// because the cap line is one dotted path stepping across all seven days —
/// a per-bar overlay would draw seven disconnected dashes and lose the shape,
/// and the shape is the point: the line falls, and the days learn to fit under
/// it.
struct TrendCard: View {
    @Bindable var record: TrendRecord
    /// Today's rows, handed in from the record home's cards already read —
    /// the graph's last bar is built from them, so a tap that moves the
    /// figure above moves the bar with it.
    let todayEntries: [StoredCheckIn]

    private var trend: Trend? { record.trend(today: todayEntries) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            header
            chart
                .frame(height: 140)
            if let trend, trend.bars.count <= 7 {
                letters(trend)
            }
            Text(captionText)
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.xl)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.extraLarge))
    }

    private var header: some View {
        HStack {
            Text(trend?.headline ?? "Nicotine over time")
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.ink)
            Spacer(minLength: AppSpacing.sm)
            spanToggle
        }
    }

    /// The board's little segmented pill: sunken track, surface thumb.
    private var spanToggle: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(TrendSpan.allCases, id: \.self) { span in
                let isOn = record.span == span
                Button {
                    Task { await record.show(span) }
                } label: {
                    Text(span.word)
                        .font(AppFont.text(AppSize.micro, isOn ? .medium : .regular))
                        .foregroundStyle(isOn ? AppColor.ink : AppColor.inkMuted)
                        .padding(.horizontal, AppSpacing.mPlus)
                        .padding(.vertical, AppSpacing.s)
                        .background {
                            if isOn { Capsule().fill(AppColor.surface) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.trend.\(span.word.lowercased())")
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AppColor.sunken, in: Capsule())
    }

    /// Bars, the stepped cap line, and the baseline — all on `Trend`'s scale.
    private var chart: some View {
        Canvas { context, size in
            guard let trend, !trend.bars.isEmpty else {
                strokeBaseline(&context, size)
                return
            }
            let bars = trend.bars
            // The board's week: 28pt bars with even gutters. A month divides
            // the same width into thinner bars rather than scrolling — the
            // card is a shape to read, not a list to traverse.
            let slot = size.width / CGFloat(bars.count)
            let barWidth = min(28, slot * 0.65)
            let floorY = size.height - 8
            let topY: CGFloat = 8
            let scale = floorY - topY

            for (index, bar) in bars.enumerated() {
                let x = slot * (CGFloat(index) + 0.5) - barWidth / 2
                let height = max(scale * bar.fraction, bar.fraction > 0 ? 2 : 0)
                let rect = CGRect(x: x, y: floorY - height, width: barWidth, height: height)
                let shape = Path(roundedRect: rect, cornerRadius: min(6, barWidth / 3))
                context.fill(shape, with: .color(bar.isToday ? AppColor.accent : AppColor.accentTint))
                if bar.isToday {
                    context.stroke(shape, with: .color(AppColor.accentEdge), lineWidth: 1)
                }
            }

            // One path, stepping: across each day at its cap, down at the
            // seam. Days with no cap leave a gap rather than a guess.
            var capLine = Path()
            var pen: CGPoint?
            for (index, bar) in bars.enumerated() {
                guard let capFraction = bar.capFraction else { pen = nil; continue }
                let y = floorY - scale * capFraction
                let from = CGPoint(x: slot * CGFloat(index), y: y)
                let to = CGPoint(x: slot * CGFloat(index + 1), y: y)
                if let pen, pen.y != y { capLine.move(to: pen); capLine.addLine(to: from) }
                capLine.move(to: from)
                capLine.addLine(to: to)
                pen = to
            }
            context.stroke(
                capLine,
                with: .color(AppColor.inkFaint),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            strokeBaseline(&context, size)
        }
        .accessibilityLabel(spokenChart)
        .accessibilityIdentifier("home.trend.chart")
    }

    private func strokeBaseline(_ context: inout GraphicsContext, _ size: CGSize) {
        var floorLine = Path()
        floorLine.move(to: CGPoint(x: 0, y: size.height - 8))
        floorLine.addLine(to: CGPoint(x: size.width, y: size.height - 8))
        context.stroke(floorLine, with: .color(AppColor.line), lineWidth: 1.5)
    }

    /// The weekday letters, today's in ink. Only a week gets them — thirty
    /// letters under thirty bars would be noise pretending to be labels.
    private func letters(_ trend: Trend) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(trend.bars.enumerated()), id: \.offset) { _, bar in
                Text(bar.label)
                    .font(AppFont.text(AppSize.micro, bar.isToday ? .medium : .regular))
                    .foregroundStyle(bar.isToday ? AppColor.ink : AppColor.inkMuted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// The caption is `Trend`'s sentence — or the apology, which outranks it.
    /// The noun is the span's own: a failed month called "the week" says the
    /// wrong thing about what is missing.
    var captionText: String {
        let noun = record.span.word.lowercased()
        if record.isUnavailable {
            return "Couldn't load the \(noun). Check your connection and try again."
        }
        return trend?.caption ?? "Reading the \(noun)…"
    }

    /// The chart in words: the heading's verdict and the caption's count are
    /// already text, so the bars only need to say what they cover.
    var spokenChart: String {
        guard let trend else { return "Nicotine over time, loading" }
        return "Nicotine over time, \(trend.bars.count) days. \(trend.headline). \(trend.caption)"
    }
}
