import SwiftUI
import CoreModel
import CoreServices

/// The editable results screen (§11): the ranking with honesty badges, where any estimate is
/// one-tap correctable, a priceless/low-confidence line can be priced or removed, and a drink the
/// scan missed can be added by hand. All state lives in `ResultsViewModel` → the pure `MenuSession`;
/// this view only renders and dispatches edits.
struct ResultsView: View {
    @ObservedObject var viewModel: ResultsViewModel

    /// The drink currently open in the correction sheet (`nil` = closed).
    @State private var editing: EditableDrink?
    /// Whether the "add a drink" sheet is open.
    @State private var adding = false

    var body: some View {
        List {
            metricSection

            rankingSection

            if !viewModel.needsPrice.isEmpty {
                unsureSection
            }

            addDrinkSection

            if !viewModel.excluded.isEmpty {
                excludedSection
            }

            explainerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add a drink")
            }
        }
        .sheet(item: $editing) { drink in
            CorrectEstimateSheet(
                drink: drink,
                onSaveABV: { viewModel.correctABV(id: drink.id, to: $0) },
                onSaveSize: { viewModel.correctSize(id: drink.id, toFluidOunces: $0) },
                onSavePrice: { viewModel.setPrice(id: drink.id, dollars: $0) },
                onRemove: { viewModel.removeDrink(id: drink.id) }
            )
        }
        .sheet(isPresented: $adding) {
            AddDrinkSheet { name, abv, size, price in
                viewModel.addDrink(name: name, abv: abv, sizeFluidOunces: size, priceDollars: price)
            }
        }
    }

    // MARK: - Sections

    private var metricSection: some View {
        Section {
            Picker("Rank by", selection: $viewModel.metric) {
                ForEach(ValueMetric.allCases, id: \.self) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var rankingSection: some View {
        Section {
            if viewModel.ranked.isEmpty {
                EmptyRankState { adding = true }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.ranked) { item in
                    Button { editing = item.drink } label: {
                        RankRow(item: item, metric: viewModel.metric)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.removeDrink(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            SectionHeader(title: "Best value first", systemImage: "trophy.fill")
        }
    }

    private var unsureSection: some View {
        Section {
            ForEach(viewModel.needsPrice) { drink in
                UnsureRow(
                    drink: drink,
                    onPrice: { viewModel.setPrice(id: drink.id, dollars: $0) },
                    onRemove: { viewModel.removeDrink(id: drink.id) }
                )
            }
        } header: {
            SectionHeader(title: "Not sure about these", systemImage: "questionmark.circle.fill")
        } footer: {
            Text("We couldn't read a price for these. They may be drinks we misread, or not drinks at all. Add a price to rank one, or remove it.")
        }
    }

    private var addDrinkSection: some View {
        Section {
            Button { adding = true } label: {
                Label("Add a drink the scan missed", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.accentColor)
        }
    }

    private var excludedSection: some View {
        Section {
            ForEach(viewModel.excluded, id: \.self) { name in
                Label(name, systemImage: "nosign")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(title: "Not alcoholic", systemImage: "drop.triangle")
        } footer: {
            Text("Excluded from the ranking.")
        }
    }

    private var explainerSection: some View {
        Section {
            DisclosureGroup {
                CalcExplainer()
            } label: {
                Label("How this is calculated", systemImage: "function")
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Ranked row
//
// `SectionHeader`, `RankMedal`, `MetaChip`, `ProvenanceChip` and `PricePill` now live in
// `Features/Shared/ValueChips.swift` — the store calculator renders the same metric and reuses them.

private struct RankRow: View {
    let item: RankedEditable
    let metric: ValueMetric

    private var drink: EditableDrink { item.drink }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RankMedal(rank: item.rank)

            VStack(alignment: .leading, spacing: 6) {
                Text(drink.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                ChipFlow(spacing: 6, lineSpacing: 6) {
                    MetaChip(text: ValueFormat.abv(drink.abv.value))
                    MetaChip(text: ValueFormat.volume(drink.size.value.fluidOunces))
                    ProvenanceChip(isEstimated: drink.hasEstimate)
                }

                if metric == .standardDrinksPerDollar, item.value > 0, let price = drink.price {
                    let count = standardDrinks(price)
                    Text(String(format: "≈ %.1f standard drink%@ · $%.2f per standard drink",
                                count, count == 1 ? "" : "s", 1.0 / item.value))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if drink.hasEstimate {
                    Label("Tap to correct", systemImage: "pencil")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(valueText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                if let price = drink.price {
                    PricePill(dollars: price.dollars, caption: "menu price")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var valueText: String {
        switch metric {
        case .standardDrinksPerDollar: return String(format: "%.2f/$", item.value)
        case .caloriesPerDollar:       return String(format: "%.0f cal/$", item.value)
        }
    }

    /// Standard drinks in one serving, derived from the ranking value (value = standardDrinks ÷ price)
    /// so the number shown can never disagree with how the drink was ranked.
    private func standardDrinks(_ price: Price) -> Double { item.value * price.dollars }
}

// MARK: - Small components

private struct EmptyRankState: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wineglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Nothing to rank yet")
                .font(.headline)
            Text("Add a price to a drink below, or add one the scan missed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Label("Add a drink", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - "Not sure about these" row (price it, or remove it)

private struct UnsureRow: View {
    let drink: EditableDrink
    let onPrice: (Double) -> Void
    let onRemove: () -> Void

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(drink.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(drink.name)")
            }

            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("$").foregroundStyle(.secondary)
                    TextField("0.00", text: $text)
                        .keyboardType(.decimalPad)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 120)

                Button("Add to ranking") { submit() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(parsedDollars == nil)

                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private var parsedDollars: Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private func submit() {
        guard let dollars = parsedDollars else { return }
        onPrice(dollars)
        text = ""
    }
}

// MARK: - Calculation explainer

private struct CalcExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A **standard drink** is 0.6 fl oz of pure alcohol, the amount in a 12 oz beer at 5% ABV.")
            Group {
                Text("Alcohol in a serving  =  size × ABV")
                Text("Standard drinks  =  alcohol ÷ 0.6")
                Text("Value  =  standard drinks ÷ menu price")
                Text("Price per standard drink  =  menu price ÷ standard drinks")
            }
            Divider()
            Text("So a 12 oz, 4.5% drink is 0.9 standard drinks. At an $8.50 menu price that's $9.44 per standard drink, higher than the sticker, because one glass is less than a full standard drink.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.vertical, 4)
    }
}

// MARK: - Correction sheet (§11) — edit price / ABV / size, or remove

private struct CorrectEstimateSheet: View {
    let drink: EditableDrink
    let onSaveABV: (Double) -> Void
    let onSaveSize: (Double) -> Void
    let onSavePrice: (Double) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var abvText = ""
    @State private var sizeText = ""
    @State private var priceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(drink.name).font(.headline)
                    Text("Fix the menu price or any estimate. Your value re-ranks the list.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Price") {
                        HStack {
                            Text("$")
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    Text("Menu price")
                } footer: {
                    Text("The price printed on the menu, per serving.")
                }

                Section {
                    LabeledContent("ABV") {
                        HStack {
                            TextField("%", text: $abvText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                        }
                    }
                } header: {
                    Text("Alcohol by volume")
                } footer: {
                    Text(drink.abv.isEstimated ? (drink.abv.note ?? "Estimated.") : "From the menu.")
                }

                Section {
                    LabeledContent("Size") {
                        HStack {
                            TextField("oz", text: $sizeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("oz")
                        }
                    }
                } header: {
                    Text("Serving size")
                } footer: {
                    Text(drink.size.isEstimated ? (drink.size.note ?? "Estimated.") : "From the menu.")
                }

                Section {
                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Label("Remove this drink", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                abvText = String(format: "%.1f", drink.abv.value)
                sizeText = String(format: "%.0f", drink.size.value.fluidOunces)
                priceText = drink.price.map { String(format: "%.2f", $0.dollars) } ?? ""
            }
        }
    }

    private func save() {
        if let dollars = parsed(priceText), dollars > 0, dollars != drink.price?.dollars {
            onSavePrice(dollars)
        }
        if let abv = Double(abvText), abv > 0, abv <= 100, abv != drink.abv.value {
            onSaveABV(abv)
        }
        if let size = Double(sizeText), size > 0, size != drink.size.value.fluidOunces {
            onSaveSize(size)
        }
        dismiss()
    }

    private func parsed(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}

// MARK: - Add-a-drink sheet (a drink the scan missed)

private struct AddDrinkSheet: View {
    /// name, abv, sizeFluidOunces, priceDollars?
    let onAdd: (String, Double, Double, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var priceText = ""
    @State private var abvText = "5.0"
    @State private var sizeText = "12"

    var body: some View {
        NavigationStack {
            Form {
                Section("Drink") {
                    TextField("Name (e.g. Founders All Day IPA)", text: $name)
                }

                Section {
                    LabeledContent("Price") {
                        HStack {
                            Text("$")
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    LabeledContent("ABV") {
                        HStack {
                            TextField("%", text: $abvText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                        }
                    }
                    LabeledContent("Size") {
                        HStack {
                            TextField("oz", text: $sizeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("oz")
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Leave the price blank to add it under \u{201C}Not sure about these\u{201D} and price it later.")
                }
            }
            .navigationTitle("Add a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }.disabled(!canAdd)
                }
            }
        }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (Double(abvText) ?? -1) > 0
            && (Double(sizeText) ?? -1) > 0
    }

    private func add() {
        guard let abv = Double(abvText), let size = Double(sizeText) else { return }
        let cleaned = priceText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)
        let price = Double(cleaned)
        onAdd(name, abv, size, price)
        dismiss()
    }
}
