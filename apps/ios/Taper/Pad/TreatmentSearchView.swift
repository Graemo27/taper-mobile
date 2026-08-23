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

            if case let .results(results) = record.status {
                rows(results)
            }

            Spacer(minLength: 0)
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
                TreatmentResultRow(result: result)
            }
        }
    }
}

/// One product a search found: what it is called, what kind it is, and every
/// strength it comes in.
///
/// Not selectable yet. The screen that turns a result into a key is next, and a
/// row that led nowhere would be worse than one that plainly does not move.
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    /// Every strength said out loud, because the chips are the part that
    /// decides which product this is and a listener gets them or nothing.
    var spokenText: String {
        let doses = result.strengths.map { "\($0.mg.clean) milligrams" }
            .formatted(.list(type: .and))
        return "\(result.brand), \(result.detailText), available in \(doses)"
    }
}
