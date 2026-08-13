import SwiftUI

struct JournalShellView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: JournalToken.emptyGap) {
                    Text("Nothing written down yet")
                        .font(AppFont.semibold(JournalToken.headingSize))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("Add the first thing you ate and it will appear here, under today.")
                        .font(AppFont.regular(JournalToken.bodySize))
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.trailing, JournalToken.bodyMeasureInset)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("journal.empty-state")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JournalToken.screenInset)
                .padding(.top, JournalToken.emptyTop)
            }

            Button(action: {}) {
                Label("Add something you ate", systemImage: "plus")
                    .font(AppFont.semibold(JournalToken.actionSize))
                    .frame(maxWidth: .infinity)
                    .padding(JournalToken.actionPadding)
                    .foregroundStyle(AppColor.onBrand)
                    .background(AppColor.brand)
                    .clipShape(.rect(cornerRadius: JournalToken.actionRadius))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("journal.add-button")
            .padding(.horizontal, JournalToken.screenInset)
            .padding(.top, JournalToken.footerTop)
            .padding(.bottom, JournalToken.footerBottom)
        }
        .background(AppColor.background)
    }
}

#Preview {
    JournalShellView()
        .preferredColorScheme(.light)
}
