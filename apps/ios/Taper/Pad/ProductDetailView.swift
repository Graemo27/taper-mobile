import SwiftUI

/// L5 — one licensed product, read off its own label.
///
/// The screen exists for the Drug Facts panel: the label is the only honest
/// source for what a piece contains, and the copy under the figure says so at
/// length — label mg is a tracking number, not a blood measurement. The write
/// it offers is the catalogue's own check-in door, for a product that never
/// made it onto the pad.
struct ProductDetailView: View {
    @Bindable var record: ProductDetailRecord
    let onBack: () -> Void
    /// Hands the row up so the day folds it in without a re-read.
    let onLogged: (StoredCheckIn) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backRow

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    heading
                    strength
                    if record.isCountable {
                        count
                    }
                    drugFacts
                    if record.isCountable {
                        total
                    } else {
                        sprayNote
                    }
                    honesty
                    if let note = record.failureText {
                        Text(note)
                            .font(AppFont.text(AppSize.caption))
                            .foregroundStyle(AppColor.cautionInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, AppSpacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)

            if record.isCountable {
                logButton
            }
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.vertical, AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    private var backRow: some View {
        Button(action: onBack) {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                Text("Log")
                    .font(AppFont.text(AppSize.body, .medium))
            }
            .foregroundStyle(AppColor.ink)
            .frame(height: AppLayout.tap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("facts.back")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(record.product.brand)
                .font(AppFont.display(AppSize.title))
                .foregroundStyle(AppColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(record.subtitleText)
                .font(AppFont.text(AppSize.label))
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    private var strength: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Strength")
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            HStack(spacing: AppSpacing.sm) {
                ForEach(record.product.strengths.map(\.mg), id: \.self) { mg in
                    strengthChip(mg)
                }
            }
        }
    }

    private func strengthChip(_ mg: Double) -> some View {
        let isChosen = record.mg == mg
        return Button { record.choose(mg) } label: {
            Text("\(mg.clean) mg")
                .font(AppFont.text(AppSize.label, .medium))
                .foregroundStyle(AppColor.ink)
                .padding(.horizontal, AppSpacing.xl)
                .frame(height: AppLayout.tap)
                .background {
                    if isChosen {
                        Capsule().fill(AppColor.accent)
                    } else {
                        Capsule().fill(AppColor.surface)
                        Capsule().strokeBorder(AppColor.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("facts.strength.\(mg.clean)")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var count: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(record.quantityText)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(record.usageText)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
            Spacer(minLength: AppSpacing.sm)
            HStack(spacing: AppSpacing.m) {
                stepButton("minus", delta: -1, filled: false)
                stepButton("plus", delta: 1, filled: true)
            }
        }
    }

    private func stepButton(_ glyph: String, delta: Int, filled: Bool) -> some View {
        Button { record.add(delta) } label: {
            Image(systemName: glyph)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(filled ? AppColor.inkInverse : AppColor.ink)
                .frame(width: AppLayout.tap, height: AppLayout.tap)
                .background {
                    if filled {
                        Circle().fill(AppColor.ink)
                    } else {
                        Circle().fill(AppColor.surface)
                        Circle().strokeBorder(AppColor.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("facts.\(glyph)")
        .accessibilityLabel(delta > 0 ? "One more" : "One fewer")
    }

    /// The panel the screen exists for, drawn the way the label draws it:
    /// a ruled box, a heavy ruled heading, and the facts in rows.
    private var drugFacts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Drug Facts")
                .font(AppFont.display(AppSize.heading))
                .foregroundStyle(AppColor.ink)
                .padding(.bottom, AppSpacing.sm)
            Rectangle().fill(AppColor.ink).frame(height: 2)
            factRow(record.ingredientHeading, record.activeIngredientText)
            Rectangle().fill(AppColor.line).frame(height: 1)
            factRow("Purpose", "Stop smoking aid")
        }
        .padding(AppSpacing.l)
        .background(AppColor.surface)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.panel)
                .strokeBorder(AppColor.ink, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("facts.panel")
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AppFont.text(AppSize.caption))
                .foregroundStyle(AppColor.inkMuted)
            Spacer(minLength: AppSpacing.sm)
            Text(value)
                .font(AppFont.text(AppSize.caption, .medium))
                .foregroundStyle(AppColor.ink)
        }
        .padding(.vertical, AppSpacing.mPlus)
    }

    /// Where this will land, and how much. Not the board's "Counts toward
    /// today": that artboard predates the two ledgers, and a treatment does
    /// not count toward the ceiling — saying so here would make using the
    /// treatment look like spending the cap.
    private var total: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Logs to your treatment")
                .font(AppFont.text(AppSize.label))
                .foregroundStyle(AppColor.inkMuted)
            Spacer(minLength: AppSpacing.sm)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(record.totalText.replacingOccurrences(of: " mg", with: ""))
                    .font(AppFont.display(AppSize.metric))
                Text("mg")
                    .font(AppFont.display(AppSize.unitSmall))
            }
            .foregroundStyle(AppColor.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Logs to your treatment, \(record.totalText)")
    }

    /// A spray gets the facts and not the write — its label lists a
    /// concentration, and counting sprays at that number would record twenty
    /// times the dose.
    private var sprayNote: some View {
        Text(ProductDetailRecord.sprayNote)
            .font(AppFont.text(AppSize.label))
            .lineSpacing(AppLeading.normal - AppSize.label)
            .foregroundStyle(AppColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AppSpacing.m)
            .background(AppColor.sunken, in: RoundedRectangle(cornerRadius: AppRadius.small))
            .accessibilityIdentifier("facts.sprayNote")
    }

    private var honesty: some View {
        Text(Self.labelNote)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var logButton: some View {
        Button {
            Task {
                if let stored = await record.log() { onLogged(stored) }
            }
        } label: {
            Text(record.status == .logging ? "Logging…" : "Add to check-in")
                .font(AppFont.text(AppSize.bodyLarge, .medium))
                .foregroundStyle(AppColor.inkInverse)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.action)
                .background(AppColor.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(record.status == .logging || record.status == .logged)
        .accessibilityIdentifier("facts.log")
    }

    /// The board's honesty paragraph, verbatim: what the number is for, and
    /// what it is not.
    static let labelNote = """
        Label mg, from the FDA Drug Facts panel. What your body actually \
        absorbs varies widely by product — there is no fixed fraction — so \
        this number is for tracking yourself consistently, not a blood \
        measurement. It works best while you stay on the same product.
        """
}
