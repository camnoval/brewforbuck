//
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
/// and see them ranked by the same metric the menu scanner uses, standard drinks per dollar, plus
/// the dollars-per-standard-drink a shopper actually compares.
///
/// The add flow is **search first**. Typing two or three letters of a product name is the fastest
/// path to a filled-in form, and a picked product brings its own strength and package shape with it
/// (a wine opens at 750 mL, a Coors at a 12 oz six pack), so most additions need only a price. A
/// product the catalog doesn't carry falls through to a blank form, so search is the front door and
/// never a wall.
///
/// State lives in `CompareViewModel` and the pure `StoreSession`. This view renders and dispatches.
struct CompareView: View {
    @StateObject private var viewModel = CompareViewModel(catalog: BundledStoreCatalog.shared)

    /// The product currently open in the edit sheet (`nil` = closed).
    @State private var editing: EditableProduct?
    /// Whether the add flow is open.
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
            AddProductFlow(viewModel: viewModel)
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
            Text("Add what's on the shelf and we'll rank it by how much alcohol you get per dollar, the same measure the menu scanner uses, applied to the whole package.")
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
                Label("Search for a product", systemImage: "magnifyingglass")
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
        PriceText.parse(priceText)
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
            Text("Search for a six pack, a bottle of wine, a handle of whiskey, then add what the tag says.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Search for a product", action: onAdd)
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
            Text("Picking a product fills in its typical strength and package. That strength is an estimate and is flagged as one. Type the number off the label and the flag clears.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

// MARK: - Add flow: search, then the form

/// Search comes first. The field is focused on open, results rank live as you type, and picking one
/// pushes a form that is already filled in except for the price.
private struct AddProductFlow: View {
    @ObservedObject var viewModel: CompareViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool

    @State private var query = ""
    @State private var prefill: ProductPrefill?
    /// Cached rather than recomputed in `body`: SwiftUI evaluates a body several times per
    /// keystroke, and once this catalog is tens of thousands of products that is the difference
    /// between typing smoothly and typing through treacle.
    @State private var matches: [CatalogProduct] = []

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search products", text: $query)
                            .focused($searchFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button {
                                query = ""
                                searchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear search")
                        }
                    }
                } footer: {
                    Text("\(viewModel.searchableProductCount) products. Picking one fills in its typical strength and usual package, so you only add the price.")
                }

                if trimmedQuery.isEmpty {
                    Section {
                        SearchHintRow()
                    }
                } else if matches.isEmpty {
                    Section {
                        Text("Nothing matched \"\(trimmedQuery)\".")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        manualEntryButton
                    }
                } else {
                    Section {
                        ForEach(matches) { product in
                            Button {
                                prefill = viewModel.prefill(for: product)
                            } label: {
                                CatalogRow(product: product)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        SectionHeader(title: "Matches", systemImage: "list.bullet")
                    }

                    Section {
                        manualEntryButton
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add a product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $prefill) { filled in
                ProductForm(prefill: filled) { draft in
                    viewModel.addProduct(
                        name: draft.name,
                        unitFluidOunces: draft.unitFluidOunces,
                        count: draft.count,
                        abv: draft.abv,
                        abvIsEstimated: draft.abvIsEstimated,
                        abvNote: draft.abvNote,
                        priceDollars: draft.priceDollars
                    )
                    dismiss()
                }
            }
            .onChange(of: query) { _, newValue in
                matches = viewModel.search(newValue)
            }
            .task {
                // A sheet's first responder isn't settled the instant it appears, so give the
                // keyboard a beat before claiming focus or it silently doesn't take.
                try? await Task.sleep(nanoseconds: 350_000_000)
                searchFocused = true
            }
        }
    }

    private var manualEntryButton: some View {
        Button {
            prefill = viewModel.blankPrefill(named: trimmedQuery)
        } label: {
            Label(trimmedQuery.isEmpty ? "Enter a product by hand" : "Add \"\(trimmedQuery)\" by hand",
                  systemImage: "square.and.pencil")
        }
    }
}

private struct SearchHintRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Start typing a product name")
                .font(.subheadline.weight(.semibold))
            Text("Try \"coors\", \"cabernet\", \"tito\". You can also enter anything by hand if it isn't listed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CatalogRow: View {
    let product: CatalogProduct

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let abv = product.abv {
                        MetaChip(text: ValueFormat.abv(abv))
                    }
                    MetaChip(text: suggestedPackage)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Show the package the form will open with, so the pick is predictable before tapping.
    private var suggestedPackage: String {
        let suggestion = PackageDefaults.suggest(
            name: product.name,
            category: product.category,
            containerMilliliters: product.containerMilliliters,
            unitsPerPackage: product.unitsPerPackage
        )
        return ValueFormat.package(count: suggestion.count,
                                   unitOunces: suggestion.container.volume.fluidOunces)
    }
}

// MARK: - The form, opened prefilled

/// What the form produces.
struct ProductDraft {
    var name: String
    var unitFluidOunces: Double
    var count: Int
    var abv: Double
    var abvIsEstimated: Bool
    var abvNote: String
    var priceDollars: Double?
}

private struct ProductForm: View {
    let prefill: ProductPrefill
    let onAdd: (ProductDraft) -> Void

    @State private var name: String
    @State private var sizeChoice: SizeChoice
    @State private var customOunces = ""
    @State private var count: Int
    @State private var abvText: String
    @State private var priceText = ""

    /// The strength as the catalog offered it. While the field still holds this exact text the
    /// value is an estimate; overtype it and it becomes a reading off the label (§11).
    private let seededABVText: String
    private let sizeOptions: [ContainerSize]

    init(prefill: ProductPrefill, onAdd: @escaping (ProductDraft) -> Void) {
        self.prefill = prefill
        self.onAdd = onAdd

        let seeded = prefill.abvIsEstimated ? ProductForm.trimZeros(prefill.abv) : ""
        self.seededABVText = seeded

        _name = State(initialValue: prefill.name)
        _count = State(initialValue: prefill.count)
        _abvText = State(initialValue: prefill.abv > 0 ? ProductForm.trimZeros(prefill.abv) : "")
        _sizeChoice = State(initialValue: .preset(prefill.container))

        // A catalog size can be one no picker carries (a 14.9 oz can), so make sure the prefilled
        // container is always among the options rather than silently snapping to something else.
        if ContainerSize.presets.contains(prefill.container) {
            self.sizeOptions = ContainerSize.presets
        } else {
            self.sizeOptions = [prefill.container] + ContainerSize.presets
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }

            Section {
                Picker("Container", selection: $sizeChoice) {
                    ForEach(sizeOptions) { option in
                        Text(option.label).tag(SizeChoice.preset(option))
                    }
                    Text("Other").tag(SizeChoice.custom)
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
                VStack(alignment: .leading, spacing: 4) {
                    if abvIsEstimated, !prefill.abvNote.isEmpty {
                        Label(prefill.abvNote, systemImage: "info.circle")
                    }
                    Text("Leave the price blank if you haven't seen the tag yet. It waits in its own list rather than being guessed at.")
                }
            }
        }
        .navigationTitle("Add a product")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(!isValid)
            }
        }
    }

    // MARK: Validation and submit

    private var unitOunces: Double? {
        switch sizeChoice {
        case .preset(let option):
            return option.volume.fluidOunces
        case .custom:
            guard let value = Double(customOunces), value > 0 else { return nil }
            return value
        }
    }

    private var abv: Double? {
        guard let value = Double(abvText), value >= 0, value <= 100 else { return nil }
        return value
    }

    private var abvIsEstimated: Bool {
        !seededABVText.isEmpty && abvText == seededABVText
    }

    /// A price is optional because it can wait. A name, a size, and a strength are not.
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
                abvNote: prefill.abvNote,
                priceDollars: PriceText.parse(priceText)
            )
        )
    }

    /// "4.2" rather than "4.200000", and "40" rather than "40.0".
    static func trimZeros(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.001
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", value)
    }
}

/// A `Picker` needs a `Hashable` selection, and `ContainerSize` alone can't express "Other".
private enum SizeChoice: Hashable {
    case preset(ContainerSize)
    case custom
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
        abvText = ProductForm.trimZeros(product.abv.value)
        ouncesText = ProductForm.trimZeros(product.unitVolume.fluidOunces)
        count = product.count
        if let price = product.price {
            priceText = String(format: "%.2f", price.dollars)
        }
    }

    /// Each axis saves independently, so a blank or nonsense field simply changes nothing. A
    /// non-positive price is refused by `Price` in Core regardless (§10).
    private func save() {
        if let ounces = Double(ouncesText), ounces > 0 {
            onSavePackage(ounces, count)
        } else if count != product.count {
            onSavePackage(product.unitVolume.fluidOunces, count)
        }
        if let abv = Double(abvText), abv >= 0, abv <= 100, abv != product.abv.value {
            onSaveABV(abv)
        }
        if let price = PriceText.parse(priceText) {
            onSavePrice(price)
        }
        dismiss()
    }
}

/// One place that turns typed money into a number, so "$14.99" and " 14.99 " behave the same
/// everywhere and a non-positive amount is rejected before it reaches Core.
enum PriceText {
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "")
                          .replacingOccurrences(of: ",", with: "")
                          .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}

#Preview {
    NavigationStack { CompareView() }
}
