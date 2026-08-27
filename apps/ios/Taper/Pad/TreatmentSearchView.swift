import SwiftUI

/// L3a — searching the licensed catalogue for something to taper with.
///
/// Lives inside the log tab rather than on top of it, which is how the board
/// draws it: the pad's own readout stays put and the keys are replaced, so
/// searching reads as a thing the pad is doing rather than a place you have
/// gone.
struct TreatmentSearchView: View {
    @Bindable var record: TreatmentSearchRecord
    let onCancel: () -> Void
    /// A product the user chose. The search does not make the key itself —
    /// naming it and choosing a strength is a screen of its own.
    let onPick: (NRTResult) -> Void
    /// Opens L5 for a result: the label, before the pad.
    let onFacts: (NRTResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            field

            if let note = Self.note(for: record.status) {
                Text(note)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(
                        Self.isFailure(record.status) ? AppColor.cautionInk : AppColor.inkMuted
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The results scroll and the field does not. With a keyboard up the
            // pad has roughly a third of its height, and a column that simply
            // grew taller than that spilled off the *top* — field, query and
            // all — leaving somebody typing at something they could not see.
            //
            // The trailing `Spacer` had to go with it, and that is the half the
            // run test proves. A `Spacer` claiming the remaining space beside a
            // scroll view kept the column overflowing, and the rows' hit regions
            // stopped agreeing with where they were drawn — a result sitting in
            // plain sight above the keyboard refused the tap. Putting the
            // `Spacer` back reproduces exactly that, at exactly that position.
            //
            // `maxHeight: .infinity` bounds the scroll view so a longer list
            // cannot rebuild the same overflow. Removing it does *not* fail the
            // run test — eight products do not make enough rows to need it — so
            // it is a guard against a case nothing here covers, not the fix.
            if case let .results(results) = record.status {
                ScrollView {
                    rows(results)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var field: some View {
        HStack(spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColor.inkMuted)
                TextField("Search gum, lozenge or patch", text: $record.query)
                    .font(AppFont.text(AppSize.bodyLarge))
                    .foregroundStyle(AppColor.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityIdentifier("search.field")
            }
            .padding(.horizontal, AppSpacing.mPlus)
            .frame(height: AppLayout.action)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: AppRadius.medium))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .strokeBorder(AppColor.ink, lineWidth: 1)
            }

            Button("Cancel", action: onCancel)
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.ink)
                .accessibilityIdentifier("search.cancel")
        }
    }

    /// The line under the field: what came back, or why nothing did.
    ///
    /// Says where the answers are from and what they are for. "FDA drug facts"
    /// is not decoration — a list of nicotine products needs to say plainly
    /// that it is a licensed catalogue and not a shop. Resting names the five
    /// licensed forms for the same reason: somebody who came looking for their
    /// pouches should be told what this list is, not left to conclude the app
    /// cannot find a brand it will never carry.
    ///
    /// A pure mapping off the status rather than a read of the record, so the
    /// copy can be checked in every state without standing a search up first.
    static func note(for status: SearchStatus) -> String? {
        switch status {
        case .resting:
            return "Licensed nicotine replacement only — gum, lozenge, patch, inhaler, spray."
        case .searching:
            return "Looking…"
        case let .results(results):
            let noun = results.count == 1 ? "match" : "matches"
            return "\(results.count) \(noun) · FDA drug facts · adds to your treatment"
        case .noMatches:
            return "Nothing licensed matched that. Try the brand name on the box."
        case let .unavailable(message):
            return message
        }
    }

    /// Whether the note is reporting a fault. Only a failed lookup is, because
    /// it is the only one of these states with a retry behind it.
    static func isFailure(_ status: SearchStatus) -> Bool {
        if case .unavailable = status { return true }
        return false
    }

    private func rows(_ results: [NRTResult]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(results) { result in
                HStack(spacing: 0) {
                    Button { onPick(result) } label: {
                        TreatmentResultRow(result: result)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // The row's label lives here rather than on the row. A
                    // button whose content is already an accessibility element
                    // has two, and the inner one takes hit testing with it — a
                    // row that reads correctly and cannot be tapped.
                    //
                    // Set without `accessibilityElement(children: .ignore)`,
                    // which would replace the button with a plain element and
                    // take the button trait with it: the row would then be
                    // neither tappable nor findable as a button.
                    .accessibilityLabel(TreatmentResultRow.spokenText(for: result))
                    .accessibilityIdentifier("search.result")

                    factsButton(result)
                }
            }
        }
    }

    /// The way into L5, beside every result: the label, before the pad.
    private func factsButton(_ result: NRTResult) -> some View {
        Button { onFacts(result) } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColor.inkMuted)
                .frame(width: AppLayout.tap, height: AppLayout.tap)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drug facts for \(result.brand)")
        .accessibilityIdentifier("search.facts")
    }
}

/// One product a search found: what it is called, what kind it is, and every
/// strength it comes in.
///
/// Selectable: tapping one opens `NewTreatmentKeyView` with its brand, form and
/// licensed strengths already filled in.
struct TreatmentResultRow: View {
    let result: NRTResult

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(result.brand)
                    .font(AppFont.text(AppSize.bodyLarge, .medium))
                    .foregroundStyle(AppColor.ink)
                Text(result.detailText)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: AppSpacing.s) {
                ForEach(result.strengths.map(\.mg), id: \.self) { mg in
                    Text("\(mg.clean) mg")
                        .font(AppFont.text(AppSize.nano, .medium))
                        .foregroundStyle(AppColor.ink)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColor.accentTint, in: Capsule())
                }
            }
        }
        .padding(.vertical, AppSpacing.mPlus)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.line).frame(height: 1)
        }
    }

    /// Every strength said out loud, because the chips are the part that
    /// decides which product this is and a listener gets them or nothing.
    ///
    /// A static taking the product, because whatever *presents* the row has to
    /// apply it: inside a button, a row carrying its own accessibility element
    /// makes two, and the inner one takes hit testing with it — leaving a row
    /// that reads correctly and cannot be tapped.
    static func spokenText(for result: NRTResult) -> String {
        let doses = result.strengths.map { "\($0.mg.clean) milligrams" }
            .formatted(.list(type: .and))
        return "\(result.brand), \(result.detailText), available in \(doses)"
    }
}
