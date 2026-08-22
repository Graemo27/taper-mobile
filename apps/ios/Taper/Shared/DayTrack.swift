import SwiftUI

/// The day as a bar: what is logged, what a pending tap would add, and anything
/// past the ceiling.
///
/// Pulled out of `CapMeter` ahead of the second screen that needs it. The
/// rescaling that happens once somebody goes over is the part worth keeping in
/// one place — past the ceiling the bar stops being the cap and becomes the
/// projected total, so the overflow has somewhere to be drawn — and two copies
/// of that arithmetic would be free to disagree about the one number the app
/// exists to report — so the bar moves out before there are two of them, not
/// after.
struct DayTrack: View {
    let tally: TodaysTally

    var body: some View {
        GeometryReader { proxy in
            let widths = Self.segmentWidths(in: proxy.size.width, for: tally)
            // No trailing spacer. It would be another child, and `HStack`
            // spaces between children — so a full bar would reserve two gaps
            // and be given three, putting it 2pt past its own end again.
            HStack(spacing: Self.gap) {
                // Dimmed, because the pending segment sits next to it and the
                // tap about to happen has to be the brighter of the two.
                segment(AppColor.accentTintStrong, width: widths.logged)
                segment(AppColor.accent, width: widths.pending)
                segment(AppColor.over, width: widths.overflow)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
