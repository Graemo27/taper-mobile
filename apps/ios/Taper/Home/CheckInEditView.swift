import SwiftUI

/// L7a — one check-in, and the way to take it back.
///
/// A screen rather than a swipe-to-delete because of the sentence at the bottom
/// of it: somebody who mis-tapped needs telling that the milligrams come back,
/// and a gesture cannot say anything.
struct CheckInEditView: View {
    let entry: StoredCheckIn
    /// Why the last removal did not land, straight off the record — including
    /// which entry it was about, so this screen can ignore one that is not its.
    let failure: RemovalFailure?
    let isRemoving: Bool
    let onRemove: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            back
            title.padding(.top, AppSpacing.xl)
            if let perUnitText {
                Text(perUnitText)
                    .font(AppFont.text(AppSize.label))
                    .foregroundStyle(AppColor.inkMuted)
                    .padding(.top, AppSpacing.l)
            }
            contribution.padding(.top, AppSpacing.xxl)
            Text(removalNote)
                .font(AppFont.text(AppSize.caption))
                .lineSpacing(AppLeading.snug - AppSize.caption)
                .foregroundStyle(AppColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, AppSpacing.l)

            Spacer(minLength: AppSpacing.xxl)

            if let failureText {
                Text(failureText)
                    .font(AppFont.text(AppSize.caption))
                    .foregroundStyle(AppColor.over)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, AppSpacing.m)
            }
            unbuilt.padding(.bottom, AppSpacing.xl)
            removeButton
        }
        .padding(.horizontal, AppLayout.gutter)
        .padding(.top, AppSpacing.smPlus)
        .padding(.bottom, AppSpacing.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppColor.ground)
    }

    /// The board pairs this with a "Done" in the opposite corner. Done is the
    /// stepper's commit and there is no stepper yet, so shipping it would be a
    /// second control doing the first one's job.
    private var back: some View {
        BackControl(destination: "Today", action: onBack)
            .accessibilityIdentifier("edit.back")
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(entry.label)
                .font(AppFont.display(AppSize.display))
                .foregroundStyle(AppColor.ink)
            Text(whenText)
                .font(AppFont.text(AppSize.label))
                .foregroundStyle(AppColor.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }

    /// The failure to show, which is only ever this entry's.
    ///
    /// A removal that fails leaves its message on the record, and the record
    /// outlives this screen. Opening a different row would otherwise greet
    /// somebody with an apology for a removal they never attempted.
    var failureText: String? {
        guard let failure, failure.entryID == entry.id else { return nil }
        return failure.message
    }

    /// What removing this actually does to the day.
    ///
    /// Two sentences, because there are two kinds of row. A source gives its
    /// milligrams back to the cap; a treatment never spent any, so removing it
    /// changes the record and not the number. Telling somebody their cap grows
    /// when they delete a patch would be the same misreading the ledger split
    /// exists to prevent — and it would sit two lines under "Doesn't count
    /// toward your cap", contradicting it.
    var removalNote: String {
        entry.ledger == .source
            ? "Removing a check-in gives the mg back to today's cap. No judgement either way."
            : "Removing this takes it off your record. Today's cap doesn't change — treatment "
                + "never counted against it. No judgement either way."
    }

    /// "Today at 12:40 pm · pouch" — the form lowercased, because here it is an
    /// aside rather than the category heading it is on a list row.
    var whenText: String {
        "Today at \(entry.timeText) · \(entry.form.label.lowercased())"
    }

    /// "3 × 1.2 mg each", and only when there is more than one.
    ///
    /// The board draws "1 pouch / 3 mg per pouch" here whatever the count,
    /// because the line is the stepper's readout. Without the stepper that is
    /// the title and the figure below repeated in the common case, so it says
    /// the one thing neither of them does and only when it is true.
    var perUnitText: String? {
        guard entry.quantity > 1 else { return nil }
        return "\(entry.quantity) × \(entry.mg.clean) mg each"
    }

    /// What this row did to the day, and whether it counted at all.
    private var contribution: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(contributionText)
                .font(AppFont.text(AppSize.label))
                .foregroundStyle(AppColor.inkMuted)
            Spacer(minLength: AppSpacing.m)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                Text(entry.totalMg.clean)
                    .font(AppFont.display(AppSize.statement))
                    .foregroundStyle(AppColor.ink)
                Text("mg")
                    .font(AppFont.display(AppSize.unitSmall))
                    .foregroundStyle(AppColor.inkMuted)
            }
        }
        .padding(.bottom, AppSpacing.l)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppColor.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(contributionText), \(entry.totalMg.clean) milligrams")
    }

    /// Treatment is logged and never counted — a patch is what carries somebody
    /// under the cap, and adding it in would make using the treatment look like
    /// failing. The board only draws the source case; this is the other half of
    /// the sentence the pad already says on its two sections.
    var contributionText: String {
        entry.ledger == .source ? "Counts toward today" : "Doesn't count toward your cap"
    }

    /// The two of the board's controls that are not here, named rather than
    /// left as gaps.
    ///
    /// The quantity stepper needs an update path `CheckInStore` does not have.
    /// "Log another of these" needs a pad key this row cannot produce:
    /// `check_ins` keeps a snapshot of the key rather than a usable copy, so
    /// the draft would have to invent a `pad_key_id` — and that column is real
    /// provenance, so an invented one would point at the wrong row.
    private var unbuilt: some View {
        Text("""
        Changing how many, and logging another of these, both belong here and aren't built yet.
        """)
            .font(AppFont.text(AppSize.caption))
            .lineSpacing(AppLeading.snug - AppSize.caption)
            .foregroundStyle(AppColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Text(isRemoving ? "Removing…" : "Remove this check-in")
                .font(AppFont.text(AppSize.body, .medium))
                .foregroundStyle(AppColor.over)
                .frame(maxWidth: .infinity)
                .frame(height: AppLayout.tap)
        }
        .buttonStyle(.plain)
        .disabled(isRemoving)
        .accessibilityIdentifier("edit.remove")
    }
}
