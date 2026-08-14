import SwiftUI

struct SearchFlowView: View {
    @StateObject private var model: SearchModel
    @State private var selectedFood: Food?
    private let initialQuery: String
    private let fetch: @Sendable (Int) async throws -> Food

    init(
        model: SearchModel,
        initialQuery: String = "",
        fetch: @escaping @Sendable (Int) async throws -> Food = { _ in
            throw FoodSearchError("Food lookup is unavailable right now.", kind: .http)
        }
    ) {
        _model = StateObject(wrappedValue: model)
        self.initialQuery = initialQuery
        self.fetch = fetch
    }

    var body: some View {
        SearchView(model: model, initialQuery: initialQuery) { selectedFood = $0 }
            .navigationDestination(isPresented: selectionIsPresented) {
                if let selectedFood {
                    FoodDetailView(
                        model: FoodLookupModel(fetch: fetch),
                        fdcID: selectedFood.fdcId,
                        handedOff: selectedFood
                    )
                }
            }
    }

    private var selectionIsPresented: Binding<Bool> {
        Binding(get: { selectedFood != nil }, set: { if !$0 { selectedFood = nil } })
    }
}

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: SearchModel
    @State private var query: String
    @FocusState private var fieldIsFocused: Bool
    let onSelect: (Food) -> Void

    init(model: SearchModel, initialQuery: String = "", onSelect: @escaping (Food) -> Void) {
        self.model = model
        _query = State(initialValue: initialQuery)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: SearchToken.zeroGap) {
            HStack(spacing: SearchToken.itemGap) {
                HStack(spacing: SearchToken.itemGap) {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppColor.textSecondary)
                    TextField("Search a food", text: $query)
                        .font(AppFont.regular(SearchToken.fieldSize))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($fieldIsFocused)
                        .accessibilityIdentifier("search.field")
                }
                .padding(.horizontal, SearchToken.cardInset)
                .frame(height: SearchToken.fieldHeight)
                .background(AppColor.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: SearchToken.fieldRadius)
                        .stroke(AppColor.brand, lineWidth: SearchToken.fieldBorder)
                }
                .clipShape(.rect(cornerRadius: SearchToken.fieldRadius))

                Button("Cancel") { dismiss() }
                    .font(AppFont.medium(SearchToken.fieldSize))
                    .foregroundStyle(AppColor.brand)
            }
            .padding(.horizontal, SearchToken.screenInset)
            .padding(.top, SearchToken.contentTop)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SearchToken.screenInset)
                    .padding(.top, SearchToken.contentTop)
            }
            .scrollDismissesKeyboard(.never)
            .simultaneousGesture(DragGesture().onChanged { _ in fieldIsFocused = false })
        }
        .background(AppColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { fieldIsFocused = true }
        .task(id: query) {
            do {
                try await Task.sleep(for: .milliseconds(400))
                await model.search(query)
            } catch {}
        }
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .idle:
            Color.clear.accessibilityIdentifier("search.idle-state")
        case .loading:
            VStack(alignment: .leading, spacing: SearchToken.itemGap) {
                Text("Searching…").font(AppFont.regular(SearchToken.bodySize))
                    .foregroundStyle(AppColor.textSecondary)
                SearchLoadingView()
            }
        case .ready where model.foods.isEmpty:
            VStack(alignment: .leading, spacing: SearchToken.itemGap) {
                SearchMessage(
                    title: "No matches for “\(model.resolvedQuery)”",
                    message: "Food Pad looks up plain ingredients, not brands.",
                    identifier: "search.empty-state"
                )
                Button("Try “oats” instead") { query = "oats" }
                    .font(AppFont.medium(SearchToken.bodySize))
                    .foregroundStyle(AppColor.brand)
                    .padding(.horizontal, SearchToken.cardInset)
                    .padding(.vertical, SearchToken.itemGap)
                    .background(AppColor.brandSubtle)
                    .clipShape(.rect(cornerRadius: SearchToken.fieldRadius))
            }
        case .ready:
            VStack(alignment: .leading, spacing: SearchToken.itemGap) {
                Text(model.foods.count == 1 ? "1 match" : "\(model.foods.count) matches")
                    .font(AppFont.semibold(SearchToken.titleSize))
                    .accessibilityIdentifier("search.results-state")
                VStack(spacing: SearchToken.zeroGap) {
                    ForEach(Array(model.foods.enumerated()), id: \.element.id) { index, food in
                        if index > 0 { Divider().padding(.horizontal, SearchToken.cardInset) }
                        SearchResultCard(food: food)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                fieldIsFocused = false
                                onSelect(food)
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("search.result.\(food.fdcId)")
                    }
                }
                .background(AppColor.surface)
                .clipShape(.rect(cornerRadius: SearchToken.cardRadius))
            }
        case .failed:
            let message = SearchFailureMessage(model.failure)
            VStack(alignment: .leading, spacing: SearchToken.itemGap) {
                SearchMessage(
                    title: message.title,
                    message: message.body,
                    identifier: "search.failure-state"
                )
                Button("Try again") { Task { await model.search(query) } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppColor.brand)
                    .accessibilityIdentifier("search.retry-button")
                if let requestID = model.failure?.requestID {
                    Text("Reference \(requestID)").font(AppFont.regular(SearchToken.bodySize))
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }
}

private struct SearchResultCard: View {
    let food: Food

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SearchToken.compactGap) {
                Text(food.name).font(AppFont.medium(SearchToken.fieldSize)).foregroundStyle(AppColor.textPrimary)
                Text(FoodFormatting.servingSummary(food.portion))
                    .font(AppFont.regular(SearchToken.bodySize)).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            if let kcal = (food.perServing ?? food.per100g).kcal {
                Text("\(kcal) kcal").font(AppFont.medium(SearchToken.bodySize))
                    .foregroundStyle(AppColor.textSecondary).frame(width: SearchToken.energyWidth, alignment: .trailing)
            }
            Image(systemName: "chevron.right").foregroundStyle(AppColor.textSecondary)
        }
        .padding(SearchToken.cardInset)
        .accessibilityElement(children: .combine)
    }
}

private struct SearchFailureMessage {
    let title: String
    let body: String

    init(_ error: FoodSearchError?) {
        switch (error?.kind, error?.status) {
        case (.timeout, _):
            title = "Food search took too long"
            body = "It didn't come back in time. A search usually takes a couple of seconds — worth another try."
        case (.offline, _):
            title = "Can't reach food search"
            body = "Check your connection, then try again."
        case (_, 429):
            title = "Too many lookups right now"
            body = "Give it a minute and try again. Nothing you did — the food database limits how often we can ask."
        default:
            title = "Food lookup is unavailable"
            body = "This one is on our side, not yours. Your search is still here — try again in a moment."
        }
    }
}

private struct SearchMessage: View {
    let title: String
    let message: String
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SearchToken.compactGap) {
            Text(title).font(AppFont.semibold(SearchToken.titleSize))
            Text(message).font(AppFont.regular(SearchToken.bodySize)).foregroundStyle(AppColor.textSecondary)
        }
        .padding(.top, SearchToken.stateTop)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

private struct SearchLoadingView: View {
    var body: some View {
        VStack(spacing: SearchToken.itemGap) {
            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: SearchToken.cardRadius)
                    .fill(AppColor.border).frame(height: SearchToken.fieldHeight)
            }
        }
        .accessibilityLabel("Searching foods")
        .accessibilityIdentifier("search.loading-state")
    }
}
