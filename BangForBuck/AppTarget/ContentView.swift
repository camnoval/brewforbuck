import SwiftUI
import CoreModel
import CoreServices

struct ContentView: View {
    @State private var menuIndex = 0
    @State private var metric: ValueMetric = .standardDrinksPerDollar
    private let pipeline = MenuPipeline()

    private var analysis: MenuAnalysis {
        pipeline.analyze(lines: SampleMenus.all[menuIndex].lines, metric: metric)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Sample menu", selection: $menuIndex) {
                        ForEach(SampleMenus.all.indices, id: \.self) { i in
                            Text(SampleMenus.all[i].name).tag(i)
                        }
                    }
                    Picker("Rank by", selection: $metric) {
                        ForEach(ValueMetric.allCases, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Best value first") {
                    if analysis.ranked.isEmpty {
                        Text("Nothing to rank on this menu.").foregroundStyle(.secondary)
                    } else {
                        ForEach(analysis.ranked, id: \.rank) { r in
                            RankRow(ranked: r, metric: metric)
                        }
                    }
                }

                if !analysis.needsPrice.isEmpty {
                    Section("Needs a price") {
                        ForEach(analysis.needsPrice, id: \.self) { name in
                            Label(name, systemImage: "tag")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !analysis.excludedNonAlcoholic.isEmpty {
                    Section("Not alcoholic (excluded)") {
                        ForEach(analysis.excludedNonAlcoholic, id: \.self) { name in
                            Label(name, systemImage: "nosign")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Bang-for-Buck")
        }
    }
}

private struct RankRow: View {
    let ranked: RankedDrink
    let metric: ValueMetric

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(ranked.rank)")
                .font(.headline).monospacedDigit()
                .frame(width: 22, alignment: .trailing)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(ranked.drink.name).font(.headline)
                HStack(spacing: 6) {
                    Text(abvText)
                    ProvenanceBadge(isEstimated: ranked.drink.abv.isEstimated)
                }
                .font(.caption)
                if let note = ranked.drink.abv.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(valueText).font(.subheadline).bold().monospacedDigit()
                if metric == .standardDrinksPerDollar, ranked.value > 0 {
                    Text(perDrinkText).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var abvText: String {
        String(format: "%.1f%% ABV · %.0f oz", ranked.drink.abv.value, ranked.drink.size.value.fluidOunces)
    }
    private var valueText: String {
        switch metric {
        case .standardDrinksPerDollar: return String(format: "%.2f /$", ranked.value)
        case .caloriesPerDollar:       return String(format: "%.0f cal/$", ranked.value)
        }
    }
    private var perDrinkText: String {
        String(format: "$%.2f / drink", 1.0 / ranked.value)
    }
}

private struct ProvenanceBadge: View {
    let isEstimated: Bool
    var body: some View {
        Text(isEstimated ? "est" : "menu")
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background((isEstimated ? Color.orange : Color.green).opacity(0.2), in: Capsule())
            .foregroundStyle(isEstimated ? .orange : .green)
    }
}

#Preview {
    ContentView()
}
