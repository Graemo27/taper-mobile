import SwiftUI

/// L8 — the screen for the middle of a craving.
///
/// The only screen in this app that is not bookkeeping. Everything else asks
/// what happened; this is opened while it is happening, by somebody who wants
/// to use and is trying not to.
///
/// So the order is deliberate: the thing that helps comes first, the thing that
/// records comes last, and nothing on it scolds. "I used — log it" is a plain
/// link and not a confession, because a craving screen that punishes the
/// answer it does not want is one people stop opening.
struct CravingView: View {
    @Bindable var record: CravingRecord
    /// The fast-acting key to reach for, if the pad has one.
    let suggestion: StoredPadKey?
    /// Named off the user's own sources, because "the tin" is only one of them.
    let putAwayTitle: String
    let onClose: () -> Void
    /// Hands up whichever row this screen wrote — the dose it suggested or the
    /// craving that passed — so the presenter can fold it into the day and
    /// close. One craving is one screen, either way it ends.
    let onLogged: (StoredCheckIn) -> Void
    /// Opens the pad, for somebody who used something else.
    let onLogSomethingElse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            closeRow

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    heading
                    if let suggestion { takeCard(suggestion) }
                    rideItOut
                    putItAway
                    if let note = failureText {
                        Text(note)
                            .font(AppFont.text(AppSize.caption))
                            .foregroundStyle(AppColor.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            passedButton
            usedLink
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.lPlus)
        .padding(.bottom, AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
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
            .accessibilityIdentifier("craving.close")
            .accessibilityLabel("Close")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("RIGHT NOW")
                .font(AppFont.text(AppSize.caption, .medium))
                .tracking(AppTracking.eyebrow(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            Text("Let it crest.")
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)
            Text(Self.body)
                .font(AppFont.text(AppSize.bodyLarge))
                .lineSpacing(AppLeading.relaxed - AppSize.bodyLarge)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one card that is a dose, and the only one drawn in the accent.
    private func takeCard(_ key: StoredPadKey) -> some View {
        Button {
            Task {
                if let taken = await record.take(key) { onLogged(taken) }
            }
        } label: {
            HStack(spacing: AppSpacing.m) {
                NicotineMark(form: key.form)
                    .frame(width: AppLayout.tap, height: AppLayout.tap)
                    .background(AppColor.accentTint, in: Circle())
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("Take your \(key.label.lowercased()) · \(key.mg.clean) mg")
                        .font(AppFont.text(AppSize.bodyLarge, .medium))
                        .foregroundStyle(AppColor.onAccent)
                    Text("This is what it's for. Logs to your treatment.")
                        .font(AppFont.text(AppSize.caption))
                        .foregroundStyle(AppColor.onAccentMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.m)
            .background(AppColor.accent, in: RoundedRectangle(cornerRadius: AppRadius.large))
        }
        .buttonStyle(.plain)
        .disabled(record.isWriting || record.isSpent)
        .accessibilityIdentifier("craving.take")
    }

    /// Not a button, and deliberately so.
    ///
    /// The board draws a chevron here, implying a timer behind it. That screen
    /// does not exist, and a card that leads nowhere is worse than one that
    /// plainly does not move — the same call the search results made before
    /// they were selectable. The copy is the whole of what it offers for now.
    private var rideItOut: some View {
        card(title: "Ride it out", detail: "Find where it sits in your body. Don't fix it.")
            .accessibilityIdentifier("craving.rideItOut")
    }

    private var putItAway: some View {
        card(
            title: putAwayTitle,
            detail: "Having it on you is the strongest predictor there is."
        )
        .accessibilityIdentifier("craving.putItAway")
    }

    private func card(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.ink)
            Text(detail)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.m)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
    }

    /// Quiet on purpose: it is the button for the outcome the app wants, and
    /// drawing it as the loudest thing on screen would make the other answer
    /// feel like a failure.
    private var passedButton: some View {
        Button {
            Task {
                if let counted = await record.itPassed() { onLogged(counted) }
            }
        } label: {
            Text(passedLabel)
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.sunken, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(record.isWriting || record.isSpent)
        .accessibilityIdentifier("craving.itPassed")
    }

    private var usedLink: some View {
        Button(action: onLogSomethingElse) {
            Text("I used — log it. No judgement.")
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("craving.iUsed")
    }

    /// What the screen says while it is happening.
    ///
    /// Names the shape of a craving rather than instructing anybody. "You don't
    /// have to win this" is the load-bearing sentence: a person mid-craving is
    /// being asked to endure something, not to succeed at it, and framing it as
    /// a contest is what makes the loss feel total.
    static let body = """
        It will crest and fall on its own, usually inside a few minutes. You \
        don't have to win this — you just have to get through it.
        """

    /// Says "Counted" rather than coming back: the dismissal it triggers is
    /// animated, and a second tap would otherwise land on a screen still there.
    var passedLabel: String {
        switch record.status {
        case .working(.count): return "Counting…"
        case .logged(.count): return "Counted"
        // Including a take in flight. That button says what is happening to it;
        // this one has nothing to report about somebody else's write.
        case .resting, .failed, .working(.take), .logged(.take):
            return "It passed — count it"
        }
    }

    /// Only a failed count is shown, and it does not ask for a retry.
    var failureText: String? {
        if case let .failed(_, message) = record.status { return message }
        return nil
    }
}
