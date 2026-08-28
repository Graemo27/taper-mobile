import SwiftUI

/// L8a — the ride-it-out state, behind L8's second card.
///
/// Deliberately not the first thing offered. The design record demoted this
/// from the whole of the craving screen to the state behind its second card,
/// on the evidence that a craving surface should end in an action: the trial
/// that beat its control asked "will you use a lozenge right now?", and the
/// high-risk moments it studied were driven by the product being *within
/// reach* far more than by the urge itself. A timer does not address a tin.
///
/// So this is for the person who has already declined the lozenge. What it
/// offers them is two minutes of attention pointed at the body, and a way to
/// record it at the end — because the thing they did is worth counting.
struct RideView: View {
    @Bindable var record: RideRecord
    /// Counts the craving as ridden out, the way L8's own button does.
    let onPassed: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            closeRow

            Spacer(minLength: 0)

            if let ride = record.ride {
                RideRing(fraction: ride.fraction, remaining: ride.remainingText)
                    .frame(maxWidth: .infinity)
                sequence(ride)
            }

            Spacer(minLength: 0)

            if record.ride?.isDone == true {
                passedButton
            }
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.lPlus)
        .padding(.bottom, AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
        .task {
            record.begin()
            // Ends when the ride does. The loop's own condition is the bound;
            // cancellation when the screen goes away is the other.
            while record.tick(), !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.ink)
                    .frame(width: AppLayout.tap, height: AppLayout.tap)
                    .background(AppColor.surface, in: Circle())
                    .overlay { Circle().strokeBorder(AppColor.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ride.close")
            .accessibilityLabel("Close")
        }
    }

    /// The step in hand, named and asked for.
    private func sequence(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(ride.step.eyebrow)
                .font(AppFont.text(AppSize.caption, .medium))
                .tracking(AppTracking.eyebrowWide(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            Text(ride.step.instruction)
                .font(AppFont.display(AppSize.heading))
                .lineSpacing(AppLeading.heading - AppSize.heading)
                .foregroundStyle(AppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ride.step.eyebrow). \(ride.step.instruction)")
        .accessibilityIdentifier("ride.step")
    }

    /// Only once the two minutes are up. Offering it earlier would make the
    /// ring a thing to skip rather than a thing to sit through.
    private var passedButton: some View {
        Button(action: onPassed) {
            Text("It passed — count it")
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ride.itPassed")
    }
}

/// The ring, and the time left inside it.
///
/// Drawn rather than a `ProgressView`, for the reason every other mark in this
/// app is: the board's ring is one stroke at one weight on one grid, and a
/// system control styled to look like it is a fight re-fought every release.
private struct RideRing: View {
    let fraction: Double
    let remaining: String

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(AppColor.sunken, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AppColor.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
            Text(remaining)
                .font(AppFont.display(AppSize.metric))
                .foregroundStyle(AppColor.ink)
                .monospacedDigit()
        }
        .frame(width: 220, height: 220)
        // One announcement, not a ring and a number: VoiceOver reads the step
        // beneath this, and "0:30" alone says nothing about what it is left of.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remaining) left")
        .accessibilityIdentifier("ride.ring")
    }
}
