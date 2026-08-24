import SwiftUI

/// L3f — turning a search result into a key on the pad.
///
/// The sticker picker the board draws is not here yet: `pad_keys` has no column
/// for it, so a chosen sticker would be forgotten by the next read. The rest of
/// the screen is what makes a key, and a picker that silently discards its
/// answer is worse than one that has not arrived.
struct NewTreatmentKeyView: View {
    @Bindable var draft: NewKeyDraft
    let onCancel: () -> Void
    let onSaved: (StoredPadKey) -> Void

    /// The five licensed forms, in the order the board lays them out.
    private static let forms: [PadForm] = [.gum, .lozenge, .patch, .inhaler, .spray]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            // The form scrolls and the button does not. This screen is taller
            // than the room a keyboard leaves, and the one control it exists
            // for is the one that would be pushed out of reach.
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    heading
                    nameField
                    typePicker
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
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity)

            saveButton
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button("Cancel", action: onCancel)
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
                .accessibilityIdentifier("newKey.cancel")
            Text("New treatment key")
                .font(AppFont.display(AppSize.title))
                .foregroundStyle(AppColor.ink)
            Text("From the FDA label library. One tap on the pad = one of these.")
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            fieldLabel("Name")
            TextField("What you'll call it", text: $draft.name)
                .font(AppFont.text(AppSize.bodyLarge))
                .foregroundStyle(AppColor.ink)
                .autocorrectionDisabled()
                .padding(.horizontal, AppSpacing.mPlus)
                .frame(height: AppLayout.action)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .strokeBorder(AppColor.ink, lineWidth: 1)
                }
                .accessibilityIdentifier("newKey.name")
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            fieldLabel("Type")
            ChipFlow(spacing: AppSpacing.s) {
                ForEach(Self.forms, id: \.self) { form in
                    let isChosen = draft.form == form
                    Button { draft.form = form } label: {
                        Text(form.label)
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
                    .accessibilityIdentifier("newKey.form.\(form.rawValue)")
                    .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// The strength, stepped through what the product is sold at rather than typed.
    private var strengthStepper: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(Self.strengthTitle(for: draft.form))
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(Self.strengthNote(count: draft.strengths.count))
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.m) {
                stepButton("−", enabled: draft.canLower, action: draft.lower)
                Text(draft.mg.clean)
                    .font(AppFont.display(AppSize.metric))
                    .foregroundStyle(AppColor.ink)
                    .frame(minWidth: 44)
                    .accessibilityIdentifier("newKey.mg")
                stepButton("+", enabled: draft.canRaise, action: draft.raise)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func stepButton(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(glyph == "+" ? "A stronger dose" : "A weaker dose")
        .accessibilityIdentifier(glyph == "+" ? "newKey.stronger" : "newKey.weaker")
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
                .background(
                    draft.canSave ? AppColor.ink : AppColor.inkFaint,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSave)
        .accessibilityIdentifier("newKey.save")
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.text(AppSize.caption))
            .foregroundStyle(AppColor.inkMuted)
    }

    /// "Mg per lozenge", because a patch is not measured per piece.
    ///
    /// The unit is the form's own, so a patch reads as a day's wear rather than
    /// as a dose taken — the same distinction `PadKey.mg` documents, said where
    /// somebody is choosing the number.
    static func strengthTitle(for form: PadForm) -> String {
        switch form {
        case .patch: return "Mg per 24 hours"
        case .gum, .lozenge, .inhaler, .spray: return "Mg per \(form.label.lowercased())"
        case .pouch, .vape, .cigarette, .dip, .other: return "Mg each"
        }
    }

    /// Says the strengths are the product's, not a range to invent within.
    static func strengthNote(count: Int) -> String {
        count <= 1
            ? "The only strength on this label"
            : "From the Drug Facts panel — \(count) strengths"
    }

    /// Only a failed save is shown. `saving` says so on the button, and
    /// `editing` has nothing to report.
    var failureText: String? {
        if case let .failed(message) = draft.status { return message }
        return nil
    }
}
