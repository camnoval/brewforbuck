//
//  QuickCompareView.swift
//  ABV
//
//  Created by Noval, Cameron on 9/5/26.
//

import SwiftUI
import CoreModel
import CoreContracts
import CoreServices

/// **Quick comparison.** You're holding a menu and weighing two or three things. Type each one,
/// take the price off the menu, and see which is the better value. No photo, no OCR, no shelf.
///
/// It defaults to a *single serving* of each drink, which is the difference from the store
/// calculator: a wine opens at a 5 oz pour rather than a 750 mL bottle, a whiskey at 1.5 oz rather
/// than a handle. Size is a row of tappable chips so a pint, a double, or a pitcher is one tap, and
/// "how many" is there for a round without pretending that's the common case.
///
/// The ranking underneath is the same pure `StoreSession` the store calculator uses, so identical
/// numbers always produce an identical answer.
struct QuickCompareView: View {
    @StateObject private var viewModel = QuickCompareViewModel()

    @State private var editing: EditableProduct?
    @State private var adding = false

    var body: some View {
        List {
            introSection

            rankingSection

            if !viewModel.needsPrice.isEmpty {
                needsPriceSection
            }

            addSection

            explainerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Quick comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isFull)
                .accessibilityLabel("Add a drink")
            }
            ToolbarItem(placement: .topBarLeading) {
                if !viewModel.isEmpty {
                    Button("Clear", role: .destructive) { viewModel.removeAll() }
                        .font(.footnote)
                }
            }
        }
        .sheet(isPresented: $adding) {
            QuickAddDrinkSheet(viewModel: viewModel)
        }
        .sheet(item: $editing) { drink in
            ProductEditSheet(
                product: drink,
                sizeOptions: ContainerSize.pourPresets,
                countLabel: "How many you'd order",
                priceLabel: "Menu price",
                onSaveABV: { viewModel.correctABV(id: drink.id, to: $0) },
                onSavePrice: { viewModel.setPrice(id: drink.id, dollars: $0) },
                onSavePackage: { viewModel.setPour(id: drink.id, fluidOunces: $0, count: $1) },
                onRemove: { viewModel.removeDrink(id: drink.id) }
            )
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            Text("Type a few drinks off the menu with their prices and we'll show which one gives you the most for your money. Sizes and strengths start at typical values you can change with a tap.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var rankingSection: some View {
        Section {
            if viewModel.ranked.isEmpty {
                EmptyQuickState { adding = true }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.ranked) { item in
                    Button { editing = item.product } label: {
                        DrinkRow(item: item)
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
        } footer: {
            if viewModel.ranked.count == 1 {
                Text("Add another drink to compare against this one.")
            }
        }
    }

    private var needsPriceSection: some View {
        Section {
            ForEach(viewModel.needsPrice) { drink in
                QuickNeedsPriceRow(
                    drink: drink,
                    onPrice: { viewModel.setPrice(id: drink.id, dollars: $0) },
                    onRemove: { viewModel.removeDrink(id: drink.id) }
                )
            }
        } header: {
            SectionHeader(title: "Waiting on a price", systemImage: "tag")
        } footer: {
            Text("We never guess a price. Add what the menu says and it joins the ranking.")
        }
    }

    private var addSection: some View {
        Section {
            Button { adding = true } label: {
                Label("Add a drink", systemImage: "plus.circle.fill")
            }
            .disabled(viewModel.isFull)
        } footer: {
            if viewModel.isFull {
                Text("Quick comparison holds \(QuickCompareViewModel.maximumDrinks) drinks. Remove one to add another, or use Compare store prices for a longer list.")
            } else {
                Text("\(viewModel.count) of \(QuickCompareViewModel.maximumDrinks)")
            }
        }
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("A **standard drink** is 0.6 fl oz of pure alcohol, so a big weak pour and a small strong one compare fairly.")
                Text("alcohol in a serving = size × ABV")
                    .font(.caption.monospaced())
                Text("standard drinks = alcohol ÷ 0.6")
                    .font(.caption.monospaced())
                Text("value = standard drinks ÷ price")
                    .font(.caption.monospaced())
                Text("A strength we filled in for you is flagged as an estimate. Tap any drink to set the real size, strength, or price.")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        } header: {
            SectionHeader(title: "How this is calculated", systemImage: "function")
        }
    }
}

// MARK: - Rows

private struct DrinkRow: View {
    let item: RankedEditableProduct

    var body: some View {
        RankedValueRow(
            ranked: item,
            sizeChip: sizeChip,
            estimatedLabel: "typical strength",
            readLabel: "you set it",
            detailSuffix: item.product.count > 1 ? " in the round" : "",
            priceCaption: "menu price"
        )
    }

    /// A single serving reads as just its size; a round reads as "2 × 12 oz".
    private var sizeChip: String {
        ValueFormat.package(count: item.product.count,
                            unitOunces: item.product.unitVolume.fluidOunces)
    }
}

private struct QuickNeedsPriceRow: View {
    let drink: EditableProduct
    let onPrice: (Double) -> Void
    let onRemove: () -> Void

    @State private var priceText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(drink.name)
                .font(.subheadline.weight(.semibold))

            ChipFlow(spacing: 6, lineSpacing: 6) {
                MetaChip(text: ValueFormat.package(count: drink.count,
                                                   unitOunces: drink.unitVolume.fluidOunces))
                MetaChip(text: ValueFormat.abv(drink.abv.value))
            }

            HStack(spacing: 8) {
                TextField("Menu price", text: $priceText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)

                Button("Add price") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(PriceText.parse(priceText) == nil)

                Spacer(minLength: 0)

                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func submit() {
        guard let value = PriceText.parse(priceText) else { return }
        onPrice(value)
        priceText = ""
    }
}

private struct EmptyQuickState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Two drinks, one answer")
                .font(.headline)
            Text("Add the drinks you're choosing between and their menu prices.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add a drink", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Add sheet

/// One screen, no drilling: name with live suggestions, then size, strength, and price. Whatever is
/// typed is usable even if the catalog has never heard of it, because most cocktails on a real menu
/// aren't in any product database.
private struct QuickAddDrinkSheet: View {
    @ObservedObject var viewModel: QuickCompareViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    @State private var name = ""
    @State private var suggestions: [CatalogProduct] = []
    /// Set when a suggestion is tapped or the typed name is resolved, so the ABV and pour arrive
    /// filled in. `nil` until then.
    @State private var prefill: DrinkPrefill?

    @State private var ouncesText = ""
    @State private var count = 1
    @State private var abvText = ""
    @State private var priceText = ""
    /// The strength as we filled it in. While the field still holds this text the value is an
    /// estimate; overtype it and it becomes something the person actually knows (§11).
    @State private var seededABVText = ""
    @State private var abvNote = ""

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Drink name", text: $name)
                        .focused($nameFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { resolveTypedName() }

                    ForEach(suggestions) { product in
                        Button {
                            apply(viewModel.prefill(for: product))
                            suggestions = []
                        } label: {
                            HStack {
                                Text(product.name)
                                    .font(.subheadline)
                                Spacer()
                                if let abv = product.abv {
                                    Text(ValueFormat.abv(abv))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("What is it")
                } footer: {
                    Text("Pick a suggestion to fill in its strength, or just type the name off the menu and we'll estimate.")
                }

                Section {
                    SizeChipPicker(options: ContainerSize.pourPresets, ounces: $ouncesText)

                    HStack {
                        Text("Exact size")
                        Spacer()
                        TextField("fl oz", text: $ouncesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text("oz").foregroundStyle(.secondary)
                    }

                    Stepper(value: $count, in: 1...12) {
                        HStack {
                            Text("How many you'd order")
                            Spacer()
                            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Size")
                } footer: {
                    if let ounces = Double(ouncesText), ounces > 0, count > 1 {
                        Text("Total: \(ValueFormat.totalVolume(unitOunces: ounces, count: count))")
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
                        Text("Menu price")
                        Spacer()
                        TextField("price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                    }
                } header: {
                    Text("Strength and price")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if abvIsEstimated, !abvNote.isEmpty {
                            Label(abvNote, systemImage: "info.circle")
                        }
                        Text("Leave the price blank for now if you like. It waits in its own list rather than being guessed at.")
                    }
                }
            }
            .navigationTitle("Add a drink")
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
            .onChange(of: name) { _, newValue in
                let query = newValue.trimmingCharacters(in: .whitespaces)
                suggestions = query.count >= 2 ? viewModel.suggestions(for: query) : []
                // Keep the estimate current as the name changes, until the person edits a field
                // themselves. Typing "margarita" should move the strength off the beer default.
                if !query.isEmpty, abvText.isEmpty || abvText == seededABVText {
                    resolveTypedName()
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                nameFocused = true
            }
        }
    }

    // MARK: Filling in

    private func resolveTypedName() {
        guard !trimmedName.isEmpty else { return }
        apply(viewModel.prefill(forTypedName: trimmedName), keepName: true)
    }

    private func apply(_ filled: DrinkPrefill, keepName: Bool = false) {
        if !keepName { name = filled.name }
        let seeded = ValueFormat.editable(filled.abv)
        seededABVText = seeded
        abvText = seeded
        abvNote = filled.abvNote
        ouncesText = ValueFormat.editable(filled.pour.volume.fluidOunces)
    }

    // MARK: Validation and submit

    private var ounces: Double? {
        guard let value = Double(ouncesText), value > 0 else { return nil }
        return value
    }

    private var abv: Double? {
        guard let value = Double(abvText), value >= 0, value <= 100 else { return nil }
        return value
    }

    private var abvIsEstimated: Bool {
        !seededABVText.isEmpty && abvText == seededABVText
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && ounces != nil && abv != nil
    }

    private func add() {
        guard let ounces, let abvValue = abv else { return }
        viewModel.addDrink(
            name: trimmedName,
            pourFluidOunces: ounces,
            count: count,
            abv: abvValue,
            abvIsEstimated: abvIsEstimated,
            abvNote: abvNote,
            priceDollars: PriceText.parse(priceText)
        )
        dismiss()
    }
}

#Preview {
    NavigationStack { QuickCompareView() }
}
