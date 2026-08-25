import SwiftUI

/// L3h — adding something you are quitting, by hand.
///
/// No search field, and that absence is the design. Every surface that lets
/// somebody *discover* a nicotine product is restricted to licensed
/// replacement therapy, so there is no catalogue of pouches or vapes to look
/// one up in — and there must not appear to be. What is left is the two things
/// a key actually needs: what kind it is, and how strong one is.
struct NewSourceKeyView: View {
    @Bindable var draft: NewSourceDraft
    let onCancel: () -> Void
    let onSaved: (StoredPadKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            // The form scrolls and the button does not, for the reason the
            // treatment screen gives: this is taller than the room a keyboard
            // leaves, and the one control it exists for would be pushed out of
            // reach. Bounded, or a `ScrollView` in a `VStack` takes its content
            // height and nothing is constrained at all.
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    heading
                    formPicker
                    strengthStepper
                    if let note = failureText {
                        Text(note)
                            .font(AppFont.text(AppSize.caption))
                            .foregroundStyle(AppColor.over)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            saveButton
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button("Cancel", action: onCancel)
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
                .accessibilityIdentifier("newSource.cancel")
            Text("What are you quitting?")
                .font(AppFont.display(AppSize.title))
                .foregroundStyle(AppColor.ink)
            Text(Self.subtitle)
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var formPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            fieldLabel("Form")
            ChipFlow(spacing: AppSpacing.s) {
                ForEach(NewSourceDraft.sources) { source in
                    let isChosen = draft.source == source
                    Button { draft.select(source) } label: {
                        Text(Self.chipLabel(for: source))
                            .font(AppFont.text(AppSize.body, isChosen ? .medium : .regular))
                            .foregroundStyle(isChosen ? AppColor.onAccent : AppColor.ink)
                            .padding(.horizontal, AppSpacing.lPlus)
                            .frame(height: AppLayout.tap)
                            .background(isChosen ? AppColor.accent : AppColor.surface, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(
                                    isChosen ? Color.clear : AppColor.line, lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("newSource.form.\(source.rawValue)")
                    .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private var strengthStepper: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("Mg each")
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(Self.strengthNote)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.m) {
                stepButton("−", enabled: draft.canLower, action: draft.lower)
                Text(draft.mg.clean)
                    .font(AppFont.display(AppSize.metric))
                    .foregroundStyle(AppColor.ink)
                    .frame(minWidth: 44)
                    .accessibilityIdentifier("newSource.mg")
                stepButton("+", enabled: draft.canRaise, action: draft.raise)
            }
        }
    }

    private func stepButton(
        _ glyph: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(AppFont.text(AppSize.unit))
                .foregroundStyle(enabled ? AppColor.ink : AppColor.inkFaint)
                .frame(width: AppLayout.tap, height: AppLayout.tap)
                .background(AppColor.surface, in: Circle())
                .overlay { Circle().strokeBorder(AppColor.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(glyph == "+" ? "A stronger one" : "A weaker one")
        .accessibilityIdentifier(glyph == "+" ? "newSource.stronger" : "newSource.weaker")
    }

    private var saveButton: some View {
        Button {
            Task { if let stored = await draft.save() { onSaved(stored) } }
        } label: {
            Text(draft.status == .saving ? "Adding…" : "Add to my pad")
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(draft.canSave ? AppColor.ink : AppColor.inkFaint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSave)
        .accessibilityIdentifier("newSource.save")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.text(AppSize.caption))
            .foregroundStyle(AppColor.inkMuted)
    }

    /// What a chip says, which is not what the key it makes will say.
    ///
    /// Singular, because a chip is picking what kind one thing is while the key
    /// stands for all of them — "Pouch" here, "Pouches" on the pad. And `other`
    /// is "Other" rather than the form's own "Something else": that reads as a
    /// key label and is two words too long for a 44pt pill.
    static func chipLabel(for source: NicotineSource) -> String {
        source == .other ? "Other" : source.padForm.label
    }

    /// Says there is no catalogue here, before anybody goes looking for one.
    ///
    /// The treatment screen offers a search and this one cannot, and a person
    /// who has just used the other will notice. Saying why turns an apparent
    /// gap into a stated boundary.
    static let subtitle = "Form and strength, not a brand — the app doesn't keep a catalogue of these."

    /// Gives permission to be approximate, which the number deserves.
    ///
    /// Measured extraction from commercial pouches ran 38%, 24% and 52%, so the
    /// figure on the tin is not what reaches anybody in the first place. Logging
    /// the same way each day is what makes the trend true; precision here is a
    /// promise the data cannot keep.
    static let strengthNote = """
        From the tin. A rough number is fine — logging it the same way every \
        time matters more than getting it exact.
        """

    /// Only a failed save is shown. `saving` says so on the button, and
    /// `editing` has nothing to report.
    var failureText: String? {
        if case let .failed(message) = draft.status { return message }
        return nil
    }
}
