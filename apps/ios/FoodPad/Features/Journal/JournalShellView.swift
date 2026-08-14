import SwiftUI

struct JournalShellView: View {
    @StateObject private var model: JournalModel
    private let onAdd: () -> Void

    init(model: JournalModel, onAdd: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model)
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: JournalToken.emptyGap) {
                    ForEach(JournalPresentation.days(from: model.entries)) { day in
                        JournalDayView(day: day, today: model.today) { entry in
                            Task { await model.remove(entry) }
                        }
                    }
                    if let name = model.failedRemoval {
                        Text("\(name) is still here — removing it did not go through.")
                            .font(AppFont.regular(JournalToken.bodySize)).foregroundStyle(AppColor.error)
                    }
                    if !model.confirmedRemovalIDs.isEmpty {
                        Color.clear.frame(width: 1, height: 1)
                            .accessibilityElement()
                            .accessibilityIdentifier("journal.database-delete-confirmed")
                    }
                    if model.entries.isEmpty && model.status == .loading { JournalSkeleton() }
                    if model.entries.isEmpty && model.status == .ready {
                        JournalMessage(
                            title: "Nothing written down yet",
                            message: "Add the first thing you ate and it will appear here, under today.",
                            identifier: "journal.empty-state"
                        )
                    }
                    if model.status == .failed {
                        JournalMessage(
                            title: model.entries.isEmpty ? "Could not open your journal" : "Could not check for new entries",
                            message: model.entries.isEmpty
                                ? "Your entries are still saved. Try again in a moment."
                                : "This is what was here when it last read. Anything saved since may be missing.",
                            identifier: "journal.failure-state"
                        )
                        Button("Try again") { Task { await model.load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColor.brand)
                            .accessibilityIdentifier("journal.retry-button")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JournalToken.screenInset)
                .padding(.top, JournalToken.contentTop)
            }

            Button(action: onAdd) {
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
        .task { if model.loadsAutomatically { await model.load() } }
        .task { await model.followMidnights(clock: SystemMidnightClock(), calendar: .current) }
    }
}

#Preview {
    JournalShellView(model: JournalModel(today: "2026-08-14") { [] })
        .preferredColorScheme(.light)
}

private struct JournalDayView: View {
    let day: JournalDay
    let today: String
    let onRemove: (JournalEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JournalToken.dayGap) {
            HStack(alignment: .firstTextBaseline, spacing: JournalToken.emptyGap) {
                Text(JournalPresentation.heading(for: day.date, today: today))
                    .font(AppFont.semibold(JournalToken.headingSize))
                    .accessibilityIdentifier("journal.day.\(day.date)")
                Text(JournalPresentation.thingCount(day.entries.count))
                    .font(AppFont.regular(JournalToken.bodySize))
                    .foregroundStyle(AppColor.textSecondary)
            }
            VStack(spacing: JournalToken.zeroGap) {
                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.horizontal, JournalToken.screenInset) }
                    JournalEntryRow(entry: entry) { onRemove(entry) }
                }
            }
            .background(AppColor.surface)
            .clipShape(.rect(cornerRadius: JournalToken.cardRadius))
        }
        .padding(.bottom, JournalToken.sectionGap)
    }
}

private struct JournalEntryRow: View {
    let entry: JournalEntry
    let onRemove: () -> Void
    @State private var offset = 0.0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                offset = 0
                onRemove()
            } label: {
                VStack(spacing: JournalToken.removeGap) {
                    Image(systemName: "trash")
                    Text("Remove").font(AppFont.medium(JournalToken.bodySize))
                }
                .frame(width: JournalToken.removeWidth).frame(maxHeight: .infinity)
                .foregroundStyle(AppColor.onError).background(AppColor.error)
            }
            .buttonStyle(.plain).accessibilityIdentifier("journal.remove.\(entry.id)")
            .allowsHitTesting(offset < 0).accessibilityHidden(offset == 0)

            HStack(spacing: JournalToken.rowGap) {
                VStack(alignment: .leading, spacing: JournalToken.zeroGap) {
                    Text(entry.name).font(AppFont.medium(JournalToken.actionSize)).lineLimit(1)
                    if let serving = entry.servingLabel {
                        Text(serving).font(AppFont.regular(JournalToken.bodySize))
                            .foregroundStyle(AppColor.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                if let kcal = entry.kcal {
                    Text("\(kcal) kcal").font(AppFont.medium(JournalToken.bodySize))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .padding(.horizontal, JournalToken.screenInset).padding(.vertical, JournalToken.rowVertical)
            .background(AppColor.surface).contentShape(Rectangle()).offset(x: offset)
            .gesture(DragGesture().onChanged { value in
                offset = min(0, max(-JournalToken.removeWidth, value.translation.width))
            }.onEnded { value in
                offset = value.translation.width < -JournalToken.removeThreshold ? -JournalToken.removeWidth : 0
            })
            .onTapGesture { offset = 0 }
            .accessibilityElement(children: .combine).accessibilityIdentifier("journal.entry.\(entry.id)")
            .accessibilityAction(named: "Remove this entry", onRemove)
        }
        .animation(.easeOut(duration: 0.2), value: offset)
    }
}

private struct JournalMessage: View {
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: JournalToken.emptyGap) {
            Text(title).font(AppFont.semibold(JournalToken.headingSize))
            Text(message).font(AppFont.regular(JournalToken.bodySize)).foregroundStyle(AppColor.textSecondary)
                .padding(.trailing, JournalToken.bodyMeasureInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .padding(.top, JournalToken.emptyTop)
    }
}

private struct JournalSkeleton: View {
    var body: some View {
        VStack(spacing: JournalToken.emptyGap) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: JournalToken.skeletonRadius)
                    .fill(AppColor.border).frame(height: JournalToken.skeletonHeight)
            }
        }
        .accessibilityLabel("Opening your journal")
        .accessibilityIdentifier("journal.loading-state")
    }
}
