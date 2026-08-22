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
        // No gutter of its own. `PadView` pads the whole screen, and a second
        // one here would inset the meter twice — narrower than the keys below
        // it, and misaligned with them.
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

    /// The day as a bar, drawn by `DayTrack` — the same bar home's card uses.
    private var track: some View { DayTrack(tally: tally, context: .selectable) }
}

#Preview("under the cap") {
    // Padded here, because the meter no longer carries a gutter of its own.
    CapMeter(
        tally: TodaysTally(
            entries: [StoredCheckIn(id: 1, ledger: .source, label: "Pouches",
                                    form: .pouch, mg: 7.5, quantity: 1, createdAt: .now)],
            pending: PendingEntry(key: StoredPadKey(id: 1, form: .pouch, label: "Pouch",
                                                    mg: 3, position: 0, ndc: nil)),
            ceilingMg: 12
        ),
        pending: PendingEntry(key: StoredPadKey(id: 1, form: .pouch, label: "Pouch",
                                                mg: 3, position: 0, ndc: nil))
    )
    .padding(.horizontal, AppLayout.gutter)
}
