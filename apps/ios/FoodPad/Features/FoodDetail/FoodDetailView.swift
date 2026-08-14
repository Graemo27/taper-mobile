import SwiftUI

/// A food's detail: serving stepper, "High in" chips, nutrition, save and
/// favourite. Reachable by hand-off from Search or by id alone.
struct FoodDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var favourites: FavouritesModel
    @StateObject private var model: FoodLookupModel
    @StateObject private var saveModel: FoodSaveModel
    @State private var servings = 1
    let fdcID: Int
    let handedOff: Food?

    init(model: FoodLookupModel, saveModel: FoodSaveModel, fdcID: Int, handedOff: Food? = nil) {
        _model = StateObject(wrappedValue: model)
        _saveModel = StateObject(wrappedValue: saveModel)
        self.fdcID = fdcID
        self.handedOff = handedOff
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FoodDetailToken.zeroGap) {
            Button { dismiss() } label: {
                Label("Search", systemImage: "chevron.left")
                    .font(AppFont.medium(FoodDetailToken.bodySize))
                    .foregroundStyle(AppColor.brand)
            }
            .accessibilityLabel("Back to search")
            .padding(.horizontal, FoodDetailToken.screenInset)
            .padding(.top, FoodDetailToken.contentTop)

            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColor.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: fdcID) {
            servings = 1
            await model.load(fdcID: fdcID, handedOff: handedOff)
        }
        .task { await favourites.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .looking:
            FoodDetailMessage(
                title: "Looking up this food…", identifier: "food.loading-state"
            )
        case .missing:
                FoodDetailMessage(
                    title: "That food could not be found.",
                    message: "Search for it again to see its detail.",
                identifier: "food.missing-state"
            )
        case .failed:
            VStack(alignment: .leading, spacing: FoodDetailToken.itemGap) {
                FoodDetailMessage(
                    title: "Could not open this food.",
                    message: "Nothing is wrong with your entry. Try again.",
                    identifier: "food.failure-state"
                )
                RetryButton(
                    spokenLabel: "Try opening this food again", identifier: "food.retry-button"
                ) { Task { await model.load(fdcID: fdcID) } }
            }
        case .held:
            if let food = model.food {
                FoodDetailContent(food: food, servings: $servings, saveModel: saveModel)
            }
        }
    }
}

private struct FoodDetailContent: View {
    @EnvironmentObject private var favourites: FavouritesModel
    let food: Food
    @Binding var servings: Int
    @ObservedObject var saveModel: FoodSaveModel

    private var nutrients: Nutrients {
        FoodParser.scale(food.per100g, toGrams: (food.portion?.grams ?? 100) * Double(servings))
    }

    private var draft: JournalDraft {
        JournalDraft(
            fdcID: food.fdcId, name: food.name,
            servingLabel: food.portion.map { FoodFormatting.servingSummary($0, servings: Double(servings)) }
                ?? "\(100 * servings) g",
            servings: servings, grams: (food.portion?.grams ?? 100) * Double(servings),
            kcal: nutrients.kcal, proteinG: nutrients.proteinG, fibreG: nutrients.fibreG
        )
    }

    var body: some View {
        VStack(spacing: FoodDetailToken.zeroGap) {
            ScrollView {
                VStack(alignment: .leading, spacing: FoodDetailToken.itemGap) {
                    Color.clear.frame(height: FoodDetailToken.zeroGap)
                        .accessibilityElement().accessibilityLabel("Food detail")
                        .accessibilityIdentifier("food.detail.\(food.fdcId)")
                    Text(food.name).font(AppFont.semibold(FoodDetailToken.titleSize))
                    ServingCard(
                        food: food,
                        servings: Binding(
                            get: { servings },
                            set: { servings = $0; saveModel.reset(for: food.fdcId) }
                        ),
                        disabled: saveModel.status(for: food.fdcId) == .saving
                    )
                    HighInCard(claims: FoodClaims.highIn(food.per100g))
                    NutritionCard(nutrients: nutrients)
                    Text("USDA values, scaled from one standard serving. What you actually ate will vary — this is the shape of the thing, not a measurement.")
                        .font(AppFont.regular(FoodDetailToken.bodySize))
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.top, FoodDetailToken.compactGap)
                }
                .padding(.horizontal, FoodDetailToken.screenInset)
                .padding(.vertical, FoodDetailToken.contentTop)
            }
            SaveFooter(
                status: saveModel.status(for: food.fdcId),
                isFavourite: favourites.ids.contains(food.fdcId),
                onSave: { Task { await saveModel.save(draft) } },
                onFavourite: { favourites.toggle(food.fdcId) }
            )
        }
    }
}

private struct ServingCard: View {
    let food: Food
    @Binding var servings: Int
    let disabled: Bool

    var body: some View {
        HStack(spacing: FoodDetailToken.itemGap) {
            VStack(alignment: .leading, spacing: FoodDetailToken.compactGap) {
                Text(food.portion == nil ? "\(100 * servings) g" : servings == 1 ? "1 serving" : "\(servings) servings")
                    .font(AppFont.semibold(FoodDetailToken.headingSize))
                Text(food.portion.map { FoodFormatting.servingSummary($0, servings: Double(servings)) }
                    ?? "No household serving listed")
                    .font(AppFont.regular(FoodDetailToken.bodySize)).foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            Button { servings = max(1, servings - 1) } label: { Image(systemName: "minus") }
                .buttonStyle(.plain).frame(width: FoodDetailToken.controlSize, height: FoodDetailToken.controlSize)
                .overlay { Circle().stroke(AppColor.border) }
                .disabled(disabled || servings == 1)
                .accessibilityLabel(food.portion == nil ? "100 grams fewer" : "One serving fewer")
                .accessibilityIdentifier("food.servings.decrement")
            Button { servings = min(20, servings + 1) } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).frame(width: FoodDetailToken.controlSize, height: FoodDetailToken.controlSize)
                .foregroundStyle(AppColor.onBrand).background(AppColor.brand).clipShape(Circle())
                .disabled(disabled || servings == 20)
                .accessibilityLabel(food.portion == nil ? "100 grams more" : "One serving more")
                .accessibilityIdentifier("food.servings.increment")
        }
        .padding(FoodDetailToken.cardInset)
        .background(AppColor.surface)
        .clipShape(.rect(cornerRadius: FoodDetailToken.cardRadius))
    }
}

private struct SaveFooter: View {
    let status: FoodSaveModel.Status
    let isFavourite: Bool
    let onSave: () -> Void
    let onFavourite: () -> Void

    private var label: String {
        switch status {
        case .idle: "Save to today"
        case .saving: "Saving…"
        case .saved: "Saved to today"
        case .failed: "Try saving again"
        }
    }

    var body: some View {
        VStack(spacing: FoodDetailToken.itemGap) {
            HStack(spacing: FoodDetailToken.itemGap) {
                Button(label, action: onSave)
                    .font(AppFont.semibold(FoodDetailToken.bodySize))
                    .frame(maxWidth: .infinity)
                    .padding(FoodDetailToken.cardInset)
                    .foregroundStyle(AppColor.onBrand).background(AppColor.brand)
                    .clipShape(.rect(cornerRadius: FoodDetailToken.controlRadius))
                    .disabled(status == .saving)
                    .accessibilityIdentifier("food.save-button")
                Button(action: onFavourite) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .foregroundStyle(isFavourite ? AppColor.favourite : AppColor.textSecondary)
                        .frame(width: FoodDetailToken.controlSize, height: FoodDetailToken.controlSize)
                }
                .buttonStyle(.plain).background(AppColor.surface).clipShape(Circle())
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
                .accessibilityAddTraits(isFavourite ? .isSelected : [])
                .accessibilityIdentifier("food.favourite-button")
            }
            if status == .failed {
                Text("Your entry was not saved. Try again in a moment.")
                    .font(AppFont.regular(FoodDetailToken.bodySize)).foregroundStyle(AppColor.error)
            }
        }
        .padding(.horizontal, FoodDetailToken.screenInset)
        .padding(.top, FoodDetailToken.itemGap)
        .padding(.bottom, FoodDetailToken.sectionGap)
    }
}

private struct HighInCard: View {
    let claims: [String]

    var body: some View {
        if !claims.isEmpty {
            VStack(alignment: .leading, spacing: FoodDetailToken.itemGap) {
                Text("High in").font(AppFont.medium(FoodDetailToken.bodySize)).foregroundStyle(AppColor.textSecondary)
                ChipFlow(spacing: FoodDetailToken.itemGap) {
                    ForEach(claims, id: \.self) { claim in
                        Text(claim).font(AppFont.medium(FoodDetailToken.bodySize)).foregroundStyle(AppColor.brand)
                            .padding(.horizontal, FoodDetailToken.itemGap).padding(.vertical, FoodDetailToken.compactGap)
                            .background(AppColor.brandSubtle).clipShape(.rect(cornerRadius: FoodDetailToken.controlRadius))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High in \(claims.joined(separator: ", "))")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(FoodDetailToken.cardInset).background(AppColor.surface)
            .clipShape(.rect(cornerRadius: FoodDetailToken.cardRadius))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("food.high-in")
        }
    }
}

private struct NutritionCard: View {
    let nutrients: Nutrients

    var body: some View {
        VStack(alignment: .leading, spacing: FoodDetailToken.sectionGap) {
            Text("Nutrition").font(AppFont.medium(FoodDetailToken.bodySize)).foregroundStyle(AppColor.textSecondary)
            HStack(alignment: .top, spacing: FoodDetailToken.itemGap) {
                Figure(value: FoodFormatting.energy(nutrients.kcal.map(Double.init)), label: "kcal")
                Figure(value: FoodFormatting.grams(nutrients.proteinG), label: "protein")
                Figure(value: FoodFormatting.grams(nutrients.fibreG), label: "fibre")
            }
        }
        .padding(FoodDetailToken.cardInset).background(AppColor.surface)
        .clipShape(.rect(cornerRadius: FoodDetailToken.cardRadius))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("food.nutrition")
    }
}

private struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: FoodDetailToken.compactGap) {
            Text(value).font(AppFont.semibold(FoodDetailToken.valueSize))
            Text(label).font(AppFont.medium(FoodDetailToken.bodySize)).foregroundStyle(AppColor.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FoodDetailMessage: View {
    let title: String
    var message: String? = nil
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: FoodDetailToken.itemGap) {
            Text(title).font(AppFont.semibold(FoodDetailToken.headingSize))
            if let message { Text(message).font(AppFont.regular(FoodDetailToken.bodySize)).foregroundStyle(AppColor.textSecondary) }
        }
        .padding(.top, FoodDetailToken.stateTop)
        .padding(.horizontal, FoodDetailToken.screenInset)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
