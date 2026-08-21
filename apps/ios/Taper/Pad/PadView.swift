import SwiftUI

/// L3 — the pad, drawn.
///
/// Two sections in the board's order, treatment above what you are quitting,
/// with the keys three to a row. Nothing here is tappable yet: selection, the
/// running total and the check-in are the next thing, and a key that looks
/// pressable and logs nothing is worse than one that plainly does not.
struct PadView: View {
    let status: PadStatus

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lPlus) {
            switch status {
            case .loading:
                loading
            case let .ready(pad) where pad.isEmpty:
                empty
            case let .ready(pad):
                section("YOUR TREATMENT", note: nil, keys: pad.treatment)
                section(
                    "WHAT YOU'RE QUITTING",
                    note: "counts toward the ceiling",
                    keys: pad.sources
                )
            case let .unavailable(message):
                unavailable(message)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.lPlus)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    /// One ledger: its eyebrow, then its keys.
    ///
    /// A section with no keys is dropped rather than drawn empty. Somebody who
    /// declined a treatment has no treatment ledger, and a headed but empty
    /// section would read as something failing to load.
    @ViewBuilder
    private func section(_ title: String, note: String?, keys: [StoredPadKey]) -> some View {
        if !keys.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(title)
                        .font(AppFont.text(AppSize.nano, .medium))
                        .tracking(AppTracking.eyebrowWide(AppSize.nano))
                        .foregroundStyle(AppColor.inkMuted)
                    if let note {
                        // The one place the app says which ledger the cap
                        // counts. It belongs on the section rather than on each
                        // key, because it is true of the group.
                        Text(note)
                            .font(AppFont.text(AppSize.nano))
                            .foregroundStyle(AppColor.inkFaint)
                    }
                }
                .accessibilityElement(children: .combine)

                rows(of: keys)
            }
        }
    }

    /// Three to a row, laid out by hand rather than by a grid.
    ///
    /// `AppLayout` fixes the arithmetic — three keys plus two gaps is exactly
    /// the content width — so a flexible grid would only be free to disagree
    /// with it. The last row is left-aligned by padding it out, which keeps a
    /// row of one key under the first key above it rather than centred.
    private func rows(of keys: [StoredPadKey]) -> some View {
        let chunks = stride(from: 0, to: keys.count, by: 3).map {
            Array(keys[$0..<min($0 + 3, keys.count)])
        }
        return VStack(alignment: .leading, spacing: AppLayout.padGap) {
            ForEach(chunks, id: \.first?.id) { row in
                HStack(spacing: AppLayout.padGap) {
                    ForEach(row, id: \.id) { PadKeyTile(key: $0) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var loading: some View {
        HStack(spacing: AppSpacing.m) {
            ProgressView().tint(AppColor.ink)
            Text("Loading your pad…")
                .font(AppFont.text(AppSize.body))
                .foregroundStyle(AppColor.inkMuted)
        }
    }

    /// A pad with nothing on it.
    ///
    /// Reachable by anyone whose plan was saved before the pad was seeded, and
    /// by anyone whose seed failed. It says what is missing rather than showing
    /// a blank area, because a screen that is silently empty reads as broken.
    private var empty: some View {
        Text("""
        There's nothing on your pad yet. Keys are set up from what you told us during onboarding, \
        and adding them by hand is the next thing to build.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Never the same as empty. Drawing "nothing here yet" over a read that
    /// failed would invite somebody to rebuild a pad that is already on the
    /// server.
    private func unavailable(_ message: String) -> some View {
        Text(message)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.cautionInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.m)
            .background(AppColor.cautionSurface, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

#Preview {
    PadView(status: .ready(Pad(keys: [
        StoredPadKey(id: 1, form: .patch, label: "Patch", mg: 21, position: 0, ndc: nil),
        StoredPadKey(id: 2, form: .lozenge, label: "Lozenge", mg: 4, position: 1, ndc: nil),
        StoredPadKey(id: 3, form: .pouch, label: "Pouches", mg: 3, position: 0, ndc: nil),
        StoredPadKey(id: 4, form: .vape, label: "Vape", mg: 2, position: 1, ndc: nil),
        StoredPadKey(id: 5, form: .cigarette, label: "Cigarettes", mg: 1.5, position: 2, ndc: nil),
    ])))
}
