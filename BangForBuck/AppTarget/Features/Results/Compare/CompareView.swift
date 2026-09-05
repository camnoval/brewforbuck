//  CompareView.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import SwiftUI
import CoreModel
import CoreContracts
import CoreServices

/// The store calculator (Goal 2): standing in a liquor-store aisle, add the packages you're weighing
/// — a 12-pack, a 750 mL bottle, a 1.75 L handle — and see them ranked by the *same* metric the menu
/// scanner uses, standard drinks per dollar, plus the dollars-per-standard-drink a shopper actually
/// compares. No camera, no OCR: everything here is typed, so the numbers are as good as the shelf tag.
///
/// State lives in `CompareViewModel` → the pure `StoreSession`. This view only renders and dispatches
/// edits, and it reuses the medal/chip/pill vocabulary from `Features/Shared/ValueChips.swift` so a
/// ranked shelf row reads exactly like a ranked menu row.
struct CompareView: View {
    @StateObject private var viewModel = CompareViewModel()

    /// The product currently open in the edit sheet (`nil` = closed).
    @State private var editing: EditableProduct?
    /// Whether the "add a product" sheet is open.
    @State private var adding = false

    var body: some View {
        List {
            introSection

            rankingSection

            if !viewModel.needsPrice.isEmpty {
                needsPriceSection
            }

            addProductSection

            explainerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Compare prices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a product")
            }
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.isEmpty {
                    Button("Clear", role: .destructive) { viewModel.removeAll() }
                        .font(.footnote)
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddProductSheet(brands: viewModel.brands) { draft in
                viewModel.addProduct(
                    name: draft.name,
                    unitFluidOunces: draft.unitFluidOunces,
                    count: draft.count,
                    abv: draft.abv,
                    abvIsEstimated: draft.abvIsEstimated,
                    brandLabel: draft.brandLabel,
                    priceDollars: draft.priceDollars
                )
            }
        }
        .sheet(item: $editing) { product in
            EditProductSheet(
                product: product,
                onSaveABV: { viewModel.correctABV(id: product.id, to: $0) },
                onSavePrice: { viewModel.setPrice(id: product.id, dollars: $0) },
                onSavePackage: { viewModel.setPackage(id: product.id, unitFluidOunces: $0, count: $1) },
                onRemove: { viewModel.removeProduct(id: product.id) }
            )
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            Text("Add what's on the shelf and we'll rank it by how much alcohol you get per dollar — the same measure the menu scanner uses, applied to the whole package.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var rankingSection: some View {
        Section {
            if viewModel.ranked.isEmpty {
                EmptyCompareState { adding = true }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.ranked) { item in
                    Button { editing = item.product } label: {
                        ProductRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.removeProduct(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            SectionHeader(title: "Best value first", systemImage: "cart.fill")
        }
    }

    private var needsPriceSection: some View {
        Section {
            ForEach(viewModel.needsPrice) { product in
                NeedsPriceRow(
                    product: product,
                    onPrice: { viewModel.setPrice(id: product.id, dollars: $0) },
                    onRemove: { viewModel.removeProduct(id: product.id) }
                )
            }
        } header: {
            SectionHeader(title: "Waiting on a price", systemImage: "tag")
        } footer: {
            Text("We never guess a price. Add the shelf price and it joins the ranking.")
        }
    }

    private var addProductSection: some View {
        Section {
            Button { adding = true } label: {
                Label("Add a product", systemImage: "plus.circle.fill")
            }
        }
    }

    private var explainerSection: some View {
        Section {
            CompareExplainer()
        } header: {
            SectionHeader(title: "How this is calculated", systemImage: "function")
        }
    }
}

// MARK: - Ranked row

private struct ProductRow: View {
    let item: RankedEditableProduct

    private var product: EditableProduct { item.product }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RankMedal(rank: item.rank)

            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    MetaChip(text: ValueFormat.package(count: product.count,
                                                       unitOunces: product.unitVolume.fluidOunces))
                    MetaChip(text: ValueFormat.abv(product.abv.value))
                    ProvenanceChip(isEstimated: product.hasEstimate,
                                   estimatedLabel: "typical ABV",
                                   readLabel: "from label")
                }

                Text("\(ValueFormat.standardDrinks(product.totalStandardDrinks)) in the package · \(ValueFormat.perStandardDrink(item.pricePerStandardDrink))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if product.hasEstimate {
                    Label("Tap to correct", systemImage: "pencil")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.2f/$", item.standardDrinksPerDollar))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                if let price = product.price {
                    PricePill(dollars: price.dollars, caption: "pack price")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Waiting-on-a-price row

private struct NeedsPriceRow: View {
    let product: EditableProduct
    let onPrice: (Double) -> Void
    let onRemove: () -> Void

    @State private var priceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                MetaChip(text: ValueFormat.package(count: product.count,
                                                   unitOunces: product.unitVolume.fluidOunces))
                MetaChip(text: ValueFormat.abv(product.abv.value))
            }

            HStack(spacing: 8) {
                TextField("Shelf price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)

                Button("Add price") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(parsedPrice == nil)

                Spacer(minLength: 0)

                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private var parsedPrice: Double? {
        guard let value = Double(priceText.replacingOccurrences(of: "$", with: "")
                                          .trimmingCharacters(in: .whitespaces)),
              value > 0 else { return nil }
        return value
    }

    private func submit() {
        guard let value = parsedPrice else { return }
        onPrice(value)
        priceText = ""
    }
}

// MARK: - Empty state

private struct EmptyCompareState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cart")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing to compare yet")
                .font(.headline)
            Text("Add a six-pack, a bottle of wine, a handle of whiskey — anything with a price on the tag.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add a product", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Explainer

private struct CompareExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A **standard drink** is 0.6 fl oz of pure alcohol (the US definition), so a big weak package and a small strong one compare fairly.")
            Text("package alcohol = unit size × count × ABV")
                .font(.caption.monospaced())
            Text("standard drinks = package alcohol ÷ 0.6")
                .font(.caption.monospaced())
            Text("value = standard drinks ÷ price")
                .font(.caption.monospaced())
            Text("Picking a brand fills in that product's typical label ABV — an estimate, flagged as one. Type the number off the can and the flag clears.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

// MARK: - Add sheet

/// What the add form produces. Kept as a plain struct so the sheet has no dependency on the view
/// model — it hands one of these back and the caller decides what to do with it.
struct ProductDraft {
    var name: String
    var unitFluidOunces: Double
    var count: Int
    var abv: Double
    /// True while the ABV is still the catalog's label-typical figure (§11).
    var abvIsEstimated: Bool
    var brandLabel: String?
    var priceDollars: Double?
}

private struct AddProductSheet: View {
    let brands: [KnownBeverage]
    let onAdd: (ProductDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brandLabel: String?
    @State private var sizeChoice: SizeChoice = .preset(ContainerSize.can12)
    @State private var customOunces = ""
    @State private var count = 6
    @State private var abvText = ""
    /// Exactly what a brand pick wrote into `abvText`. While the field still holds that string the
    /// ABV is the catalog's label-typical figure — an estimate (§11). The moment the shopper types
    /// anything else, they've read it off the can and it's `.read`. Deriving the flag from the text
    /// (rather than tracking edits) keeps a *second* brand pick from clearing it by mistake.
    @State private var catalogABVText: String?
    @State private var priceText = ""
    @State private var pickingBrand = false

    private var abvIsEstimated: Bool {
        guard let catalogABVText else { return false }
        return abvText == catalogABVText
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)

                    Button {
                        pickingBrand = true
                    } label: {
                        HStack {
                            Label("Pick a known brand", systemImage: "list.bullet.rectangle")
                            Spacer()
                            if let brandLabel {
                                Text(brandLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                } footer: {
                    Text("Picking a brand fills in the name and its typical ABV, so you only enter size, count, and price.")
                }

                Section {
                    Picker("Container", selection: $sizeChoice) {
                        ForEach(ContainerSize.presets, id: \.label) { preset in
                            Text(preset.label).tag(SizeChoice.preset(preset))
                        }
                        Text("Other…").tag(SizeChoice.custom)
                    }

                    if sizeChoice == .custom {
                        HStack {
                            Text("Size")
                            Spacer()
                            TextField("fl oz", text: $customOunces)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                            Text("oz").foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $count, in: 1...48) {
                        HStack {
                            Text("How many")
                            Spacer()
                            Text("\(count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Package")
                } footer: {
                    if let ounces = unitOunces {
                        Text("Total: \(ValueFormat.ounces(ounces * Double(count)))")
                    }
                }

                Section {
                    HStack {
                        Text("ABV")
                        Spacer()
                        TextField("e.g. 5", text: $abvText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text("%").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("whole package", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                    }
                } header: {
                    Text("Strength and price")
                } footer: {
                    Text("Leave the price blank if you haven't seen the tag yet — it'll wait in its own list rather than be guessed at.")
                }
            }
            .navigationTitle("Add a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $pickingBrand) {
                BrandPickerSheet(brands: brands) { brand in
                    let seeded = String(format: "%g", brand.abv)
                    name = brand.label
                    brandLabel = brand.label
                    abvText = seeded
                    catalogABVText = seeded        // catalog figure — a guess until the user overtypes it
                    sizeChoice = .preset(Self.defaultContainer(for: brand.category))
                    count = Self.defaultCount(for: brand.category)
                }
            }
        }
    }

    // MARK: Validation + submit

    private var unitOunces: Double? {
        switch sizeChoice {
        case .preset(let preset):
            return preset.volume.fluidOunces
        case .custom:
            guard let value = Double(customOunces), value > 0 else { return nil }
            return value
        }
    }

    private var abv: Double? {
        guard let value = Double(abvText), value >= 0, value <= 100 else { return nil }
        return value
    }

    private var price: Double? {
        let cleaned = priceText.replacingOccurrences(of: "$", with: "")
                               .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    /// A price is optional (it can wait); a name, a size, and an ABV are not.
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && unitOunces != nil && abv != nil
    }

    private func add() {
        guard let ounces = unitOunces, let abvValue = abv else { return }
        onAdd(
            ProductDraft(
                name: name,
                unitFluidOunces: ounces,
                count: count,
                abv: abvValue,
                abvIsEstimated: abvIsEstimated,
                brandLabel: abvIsEstimated ? brandLabel : nil,
                priceDollars: price
            )
        )
        dismiss()
    }

    /// Sensible starting package for a picked brand — still fully editable.
    private static func defaultContainer(for category: BeverageCategory) -> ContainerSize {
        switch category {
        case .wineGlass, .sangria:      return ContainerSize.ml750
        case .cocktail, .frozenCocktail, .martini, .shot: return ContainerSize.ml750
        default:                        return ContainerSize.can12
        }
    }

    private static func defaultCount(for category: BeverageCategory) -> Int {
        switch category {
        case .wineGlass, .sangria, .cocktail, .frozenCocktail, .martini, .shot: return 1
        default: return 6
        }
    }
}

/// A `Picker` needs a `Hashable` selection, and `ContainerSize` alone can't express "Other…".
private enum SizeChoice: Hashable {
    case preset(ContainerSize)
    case custom
}

// MARK: - Brand picker

private struct BrandPickerSheet: View {
    let brands: [KnownBeverage]
    let onPick: (KnownBeverage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matches: [KnownBeverage] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return brands }
        return brands.filter { $0.label.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { brand in
                Button {
                    onPick(brand)
                    dismiss()
                } label: {
                    HStack {
                        Text(brand.label)
                        Spacer()
                        Text(ValueFormat.abv(brand.abv))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $query, prompt: "Search \(brands.count) products")
            .navigationTitle("Known brands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Edit sheet

private struct EditProductSheet: View {
    let product: EditableProduct
    let onSaveABV: (Double) -> Void
    let onSavePrice: (Double) -> Void
    let onSavePackage: (Double, Int) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var abvText = ""
    @State private var priceText = ""
    @State private var ouncesText = ""
    @State private var count = 1
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name).font(.headline)
                    if let note = product.abv.note {
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Package") {
                    HStack {
                        Text("Unit size")
                        Spacer()
                        TextField("fl oz", text: $ouncesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text("oz").foregroundStyle(.secondary)
                    }
                    Stepper(value: $count, in: 1...48) {
                        HStack {
                            Text("How many")
                            Spacer()
                            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Strength and price") {
                    HStack {
                        Text("ABV")
                        Spacer()
                        TextField("%", text: $abvText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text("%").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("whole package", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("Remove this product", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        abvText = String(format: "%g", product.abv.value)
        ouncesText = String(format: "%g", product.unitVolume.fluidOunces)
        count = product.count
        if let price = product.price {
            priceText = String(format: "%.2f", price.dollars)
        }
    }

    /// Each axis saves independently, so a blank or nonsense field simply doesn't change anything —
    /// and a non-positive price is refused by `Price` in Core regardless (§10).
    private func save() {
        if let ounces = Double(ouncesText), ounces > 0 {
            onSavePackage(ounces, count)
        } else if count != product.count {
            onSavePackage(product.unitVolume.fluidOunces, count)
        }
        if let abv = Double(abvText), abv >= 0, abv <= 100, abv != product.abv.value {
            onSaveABV(abv)
        }
        let cleanedPrice = priceText.replacingOccurrences(of: "$", with: "")
                                    .trimmingCharacters(in: .whitespaces)
        if let price = Double(cleanedPrice), price > 0 {
            onSavePrice(price)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { CompareView() }
}
