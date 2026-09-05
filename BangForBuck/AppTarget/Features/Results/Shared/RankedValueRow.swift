//
//  RankedValueRow.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import SwiftUI
import CoreModel
import CoreServices

/// One ranked line in a value comparison, whatever is being compared. The store calculator ranks
/// packages, the quick comparison ranks single pours, and the menu scanner ranks menu items; they
/// are all "here is a rank, a name, some chips, and what it costs per standard drink", so they
/// share one row rather than three that drift apart.
struct RankedValueRow: View {
    let rank: Int
    let name: String
    /// Small grey facts: the package or pour, the strength.
    let chips: [String]
    let isEstimated: Bool
    let estimatedLabel: String
    let readLabel: String
    /// The line under the chips, usually standard drinks plus cost per standard drink.
    let detail: String
    let valueText: String
    let priceDollars: Double?
    let priceCaption: String
    /// Show the "tap to correct" nudge. Only worth it when something is actually estimated.
    var showsCorrectHint: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RankMedal(rank: rank)

            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                        MetaChip(text: chip)
                    }
                    ProvenanceChip(isEstimated: isEstimated,
                                   estimatedLabel: estimatedLabel,
                                   readLabel: readLabel)
                }

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if showsCorrectHint {
                    Label("Tap to change", systemImage: "slider.horizontal.3")
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
                if let priceDollars {
                    PricePill(dollars: priceDollars, caption: priceCaption)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Build the row from an `EditableProduct` the way both comparison screens want it. Kept as a
/// function rather than another view type so there's exactly one place deciding what the chips say.
extension RankedValueRow {
    init(
        ranked: RankedEditableProduct,
        sizeChip: String,
        estimatedLabel: String,
        readLabel: String,
        detailSuffix: String,
        priceCaption: String
    ) {
        let product = ranked.product
        self.init(
            rank: ranked.rank,
            name: product.name,
            chips: [sizeChip, ValueFormat.abv(product.abv.value)],
            isEstimated: product.hasEstimate,
            estimatedLabel: estimatedLabel,
            readLabel: readLabel,
            detail: "\(ValueFormat.standardDrinks(product.totalStandardDrinks))\(detailSuffix) · \(ValueFormat.perStandardDrink(ranked.pricePerStandardDrink))",
            valueText: String(format: "%.2f/$", ranked.standardDrinksPerDollar),
            priceDollars: product.price?.dollars,
            priceCaption: priceCaption,
            showsCorrectHint: product.hasEstimate
        )
    }
}

// MARK: - Edit sheet

/// Change any variable after the fact: size, how many, strength, price, or remove it. Shared by
/// both comparisons, with the labels supplied by the caller because "how many" means "cans in the
/// pack" in a store and "rounds you'd order" at a bar.
struct ProductEditSheet: View {
    let product: EditableProduct
    let sizeOptions: [ContainerSize]
    let countLabel: String
    let priceLabel: String
    let onSaveABV: (Double) -> Void
    let onSavePrice: (Double) -> Void
    let onSavePackage: (Double, Int) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var abvText = ""
    @State private var priceText = ""
    /// Canonical, always fluid ounces. The chip picker writes here.
    @State private var ouncesText = ""
    /// What the text field shows: millilitres for a bottle size, ounces otherwise.
    @State private var sizeText = ""
    @State private var isMetric = false
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

                Section("Size") {
                    SizeChipPicker(options: sizeOptions, ounces: $ouncesText)

                    // The field follows the unit the size is stated in. Nobody knows a wine bottle
                    // as 25.4 oz, so a metric container is edited in millilitres and converted on
                    // the way in and out; a can stays in ounces.
                    HStack {
                        Text("Exact size")
                        Spacer()
                        TextField(isMetric ? "mL" : "fl oz", text: $sizeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text(isMetric ? "mL" : "oz").foregroundStyle(.secondary)
                    }

                    Stepper(value: $count, in: 1...48) {
                        HStack {
                            Text(countLabel)
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
                        Text(priceLabel)
                        Spacer()
                        TextField("price", text: $priceText)
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
                        Label("Remove this one", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Change details")
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
            // A chip tap writes ounces; mirror it into the field in whichever unit reads better.
            .onChange(of: ouncesText) { _, newValue in
                guard let ounces = Double(newValue), ounces > 0 else { return }
                let metric = ValueFormat.isMetricSize(ounces)
                let shown = metric
                    ? ValueFormat.editable(ounces * ValueFormat.millilitersPerOunce)
                    : ValueFormat.editable(ounces)
                if shown != sizeText || metric != isMetric {
                    isMetric = metric
                    sizeText = shown
                }
            }
            // Typing in the field writes back to the canonical ounces.
            .onChange(of: sizeText) { _, newValue in
                guard let typed = Double(newValue), typed > 0 else { return }
                let ounces = isMetric ? typed / ValueFormat.millilitersPerOunce : typed
                let canonical = ValueFormat.editable(ounces)
                if canonical != ouncesText { ouncesText = canonical }
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        abvText = ValueFormat.editable(product.abv.value)

        let ounces = product.unitVolume.fluidOunces
        ouncesText = ValueFormat.editable(ounces)
        isMetric = ValueFormat.isMetricSize(ounces)
        sizeText = isMetric
            ? ValueFormat.editable(ounces * ValueFormat.millilitersPerOunce)
            : ValueFormat.editable(ounces)

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

// MARK: - Size chips

/// A horizontal strip of tappable sizes, so changing a pour or a can size is one tap instead of a
/// picker and a keyboard. Writes straight into the same ounces field the text box edits, so the two
/// controls can never disagree.
struct SizeChipPicker: View {
    let options: [ContainerSize]
    @Binding var ounces: String

    private var selected: Double? { Double(ounces) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let isOn = isSelected(option)
                    Button {
                        ounces = ValueFormat.editable(option.volume.fluidOunces)
                    } label: {
                        Text(option.label)
                            .font(.caption.weight(isOn ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func isSelected(_ option: ContainerSize) -> Bool {
        guard let selected else { return false }
        return abs(option.volume.fluidOunces - selected) < 0.05
    }
}
