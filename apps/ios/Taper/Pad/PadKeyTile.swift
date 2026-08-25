import SwiftUI

/// One key on the pad, as the board draws it: a 110pt square with a mark, a
/// name and the strength it logs.
///
/// The strength sits in a tinted pill whose colour is the ledger — accent for
/// what helps, source-tint for what counts against the day's ceiling. That is
/// the only place the two ledgers differ visually inside a key, and it is
/// deliberately not the label: a key someone taps at speed is read by shape and
/// colour before it is read as words.
struct PadKeyTile: View {
    let key: StoredPadKey
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) { face }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(key.label), \(key.mg.clean) milligrams")
            .accessibilityAddTraits(.isButton)
    }

    /// The key itself.
    ///
    /// Deliberately no selected state. The board shows a selection once, in the
    /// readout above the meter, and never on the key — a pad tapped at speed is
    /// read at the top, and marking the key as well would be the same fact in
    /// two places, free to disagree while a write is in flight.
    private var face: some View {
        VStack(spacing: AppSpacing.s) {
            if NicotineMark.isDrawn(key.form) {
                // Tilted here rather than inside the mark, because a pouch is
                // the one thing on this pad nobody sets down square — and the
                // log's rows lean the whole tile instead, so a mark carrying
                // its own angle would arrive there crooked and be tilted twice.
                NicotineMark(form: key.form)
                    .rotationEffect(.degrees(key.form == .pouch ? -5 : 0))
            }
            Text(key.label)
                .font(AppFont.text(AppSize.caption, .medium))
                .lineSpacing(AppLeading.tight - AppSize.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppColor.ink)
            strengthPill
        }
        .frame(width: AppLayout.key, height: AppLayout.key)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .strokeBorder(AppColor.line, lineWidth: 1)
        }
    }

    private var strengthPill: some View {
        Text("\(key.mg.clean) mg")
            .font(AppFont.text(AppSize.nano, .medium))
            .foregroundStyle(AppColor.ink)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(pillTint, in: Capsule())
    }

    /// Accent for treatment, source-tint for what counts against the ceiling.
    private var pillTint: Color {
        key.ledger == .treatment ? AppColor.accentTint : AppColor.sourceTint
    }
}

/// The way onto the pad: a key-shaped tile that opens the screen for adding one.
///
/// One per ledger, and they lead to different places on purpose. A treatment is
/// *found* in the licensed catalogue; what somebody is quitting is *typed* — a
/// plain form and a strength — because a catalogue of brands to browse is the
/// one thing this app must not offer for tobacco. That rule is about discovery
/// rather than recording, which is why the pad still has a way to record one.
struct AddKeyTile: View {
    /// Two words at most: the tile is a key, not a button with room for a
    /// sentence. The section heading above it carries the rest of the meaning.
    let title: String
    /// What a listener gets, where there is room to say which ledger this is.
    let spokenLabel: String
    let identifier: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.s) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColor.inkMuted)
                Text(title)
                    .font(AppFont.text(AppSize.caption, .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColor.inkMuted)
            }
            .frame(width: AppLayout.key, height: AppLayout.key)
            .background(AppColor.ground, in: RoundedRectangle(cornerRadius: AppRadius.large))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(AppColor.lineStrong)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(spokenLabel)
    }
}

extension AddKeyTile {
    /// Opens the licensed catalogue.
    static func treatment(onTap: @escaping () -> Void) -> AddKeyTile {
        AddKeyTile(
            title: "Add treatment",
            spokenLabel: "Add a treatment from the licensed product list",
            identifier: "pad.addTreatment",
            onTap: onTap
        )
    }

    /// Opens the hand-typed form.
    ///
    /// Just "Add", because the heading above already says what is being added
    /// and "source" is the app's word for it rather than anybody else's.
    static func source(onTap: @escaping () -> Void) -> AddKeyTile {
        AddKeyTile(
            title: "Add",
            spokenLabel: "Add something you are quitting",
            identifier: "pad.addSource",
            onTap: onTap
        )
    }
}
