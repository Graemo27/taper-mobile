import SwiftUI

/// The top of L3: what is about to be logged, and where it leaves the day.
///
/// Everything shown comes off `TodaysTally`, which decides what counts and what
/// is said about going over. Nothing here re-derives a figure — a screen that
/// worked out its own total would be a second answer to the one question the
/// whole app exists to answer.
struct CapMeter: View {
    let tally: TodaysTally
    /// What is selected, read back above the figure. Nil when nothing is.
    let pending: PendingEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            readout
            track.padding(.top, AppSpacing.smPlus)
            Text(tally.readout)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(tally.isOver ? AppColor.over : AppColor.inkMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, AppSpacing.sm)
        }
        .padding(.horizontal, AppLayout.gutter)
        .accessibilityElement(children: .combine)
    }

    /// The pending entry, named and totalled.
    ///
    /// The block keeps its height when nothing is selected rather than
    /// collapsing. A pad that shifts under your finger between taps is one that
    /// makes you re-aim, and the whole surface is built to be hit without
    /// looking.
    private var readout: some View {
        VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
            if let pending {
                HStack(spacing: AppSpacing.sm) {
                    Text(pending.key.label)
                        .font(AppFont.text(AppSize.label))
                        .foregroundStyle(AppColor.inkMuted)
                    Text("× \(pending.quantity)")
                        .font(AppFont.text(AppSize.label, .medium))
                        .foregroundStyle(AppColor.ink)
                }

                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(pending.totalMg.clean)
                        .font(AppFont.display(AppSize.figure))
                        .foregroundStyle(AppColor.ink)
                    Text("mg")
                        .font(AppFont.display(AppSize.unit))
                        .foregroundStyle(AppColor.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: readoutHeight, alignment: .bottomTrailing)
        .padding(.top, AppSpacing.s)
    }

    /// Label line, gap, figure line — reserved whether or not it is filled.
    private var readoutHeight: CGFloat { AppLeading.snug + AppSpacing.xxs + AppLeading.figure }

    /// The day as a bar.
    ///
    /// Three segments, and only the ones with width are drawn: what is already
    /// logged, what this tap would add, and anything past the ceiling. The
    /// fractions come from the tally, including the rescaling that happens once
    /// somebody is over — so the overflow has room to be shown rather than
    /// being flattened against a full bar.
    private var track: some View {
        GeometryReader { proxy in
            let widths = Self.segmentWidths(in: proxy.size.width, for: tally)
            HStack(spacing: Self.gap) {
                segment(AppColor.accentTintStrong, width: widths.logged)
                segment(AppColor.accent, width: widths.pending)
                segment(AppColor.over, width: widths.overflow)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(AppColor.sunken, in: Capsule())
        .clipShape(Capsule())
    }

    /// The board sets the segments 2pt apart.
    static let gap: CGFloat = 2

    /// How wide each segment is drawn.
    ///
    /// The gaps come out of the track before the fractions are applied. They
    /// sum to 1 once somebody is over the cap, so sizing each one against the
    /// full width and *then* spacing them apart puts the last segment past the
    /// end — where the capsule clip quietly eats it, which is the overflow, the
    /// one segment nobody can afford to lose.
    ///
    /// Static and pure so the arithmetic can be checked without a layout pass.
    static func segmentWidths(
        in trackWidth: CGFloat,
        for tally: TodaysTally
    ) -> (logged: CGFloat, pending: CGFloat, overflow: CGFloat) {
        let fractions = [tally.loggedFraction, tally.pendingFraction, tally.overflowFraction]
        let drawn = fractions.count { $0 > 0 }
        // Clamped once, here. `GeometryReader` reports zero before it has been
        // measured, and on a narrow enough track the gaps alone exceed it — a
        // negative frame width is a crash rather than a bad drawing. Clamping
        // each width as well would be a second guard that nothing could reach.
        let available = max(0, trackWidth - CGFloat(max(0, drawn - 1)) * gap)
        let widths = fractions.map { available * $0 }
        return (widths[0], widths[1], widths[2])
    }

    @ViewBuilder
    private func segment(_ colour: Color, width: CGFloat) -> some View {
        if width > 0 {
            Capsule().fill(colour).frame(width: width)
        }
    }
}

#Preview("under the cap") {
    CapMeter(
        tally: TodaysTally(
            entries: [StoredCheckIn(id: 1, ledger: .source, label: "Pouches",
                                    form: .pouch, mg: 7.5, quantity: 1)],
            pending: PendingEntry(key: StoredPadKey(id: 1, form: .pouch, label: "Pouch",
                                                    mg: 3, position: 0, ndc: nil)),
            ceilingMg: 12
        ),
        pending: PendingEntry(key: StoredPadKey(id: 1, form: .pouch, label: "Pouch",
                                                mg: 3, position: 0, ndc: nil))
    )
}
