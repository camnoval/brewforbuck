//
//  ValueChips.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 9/5/26.
//

import SwiftUI

/// The shared visual vocabulary for a *ranked value row*, used by both the menu results screen and
/// the store calculator. These started life as `private` structs inside `ResultsView`; the store
/// side needs the identical medal/chip/pill treatment (a shopper and a bar-goer are reading the same
/// metric), so they were lifted here rather than duplicated — one place to restyle, and the two
/// screens can't drift apart.
///
/// Presentation only. No business logic: every number arrives already computed by Core (§4).

// MARK: - Number formatting

/// The one place value-row numbers get formatted, so a size or an ABV reads the same everywhere.
enum ValueFormat {

    /// A volume in fluid ounces. Whole sizes print clean (`12 oz`), fractional ones keep one
    /// decimal (`1.5 oz`, `19.2 oz`). The old `%.0f` rounded a 1.5 oz shot to "2 oz" while the
    /// ranking correctly used 1.5 — a display-only lie about a value the user might then "correct".
    static func ounces(_ fluidOunces: Double) -> String {
        let rounded = fluidOunces.rounded()
        if abs(fluidOunces - rounded) < 0.05 {
            return String(format: "%.0f oz", rounded)
        }
        return String(format: "%.1f oz", fluidOunces)
    }

    /// An alcohol-by-volume percentage.
    static func abv(_ percent: Double) -> String {
        let rounded = percent.rounded()
        if abs(percent - rounded) < 0.05 {
            return String(format: "%.0f%% ABV", rounded)
        }
        return String(format: "%.1f%% ABV", percent)
    }

    /// A dollar amount.
    static func money(_ dollars: Double) -> String {
        String(format: "$%.2f", dollars)
    }

    /// "12 × 12 oz" for a pack, or just "750 mL"-style single-container text when count is 1.
    static func package(count: Int, unitOunces: Double) -> String {
        count > 1 ? "\(count) × \(ounces(unitOunces))" : ounces(unitOunces)
    }

    /// Standard drinks, with the singular/plural fixed up.
    static func standardDrinks(_ count: Double) -> String {
        String(format: "≈ %.1f standard drink%@", count, abs(count - 1) < 0.05 ? "" : "s")
    }

    /// "$1.67 per standard drink", or an honest note when there's no alcohol to price.
    static func perStandardDrink(_ dollars: Double) -> String {
        guard dollars.isFinite else { return "no alcohol, so no value per drink" }
        return "\(money(dollars)) per standard drink"
    }

    /// A number as it should appear in an editable text field: "4.2" not "4.200000", "40" not
    /// "40.0". Used to seed the ABV and size fields so the shopper isn't deleting stray zeros.
    static func editable(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.001
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", value)
    }
}

/// One place that turns typed money into a number, so "$14.99" and " 14.99 " behave the same
/// everywhere and a non-positive amount is rejected before it ever reaches Core (§10).
enum PriceText {
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "")
                          .replacingOccurrences(of: ",", with: "")
                          .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.caption2)
            Text(title)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(nil)
    }
}

// MARK: - Small components

/// Gold / silver / bronze for the top three, muted for the rest.
struct RankMedal: View {
    let rank: Int

    private var fill: Color {
        switch rank {
        case 1: return Color(red: 0.85, green: 0.65, blue: 0.13)   // gold
        case 2: return Color(white: 0.62)                          // silver
        case 3: return Color(red: 0.72, green: 0.45, blue: 0.20)   // bronze
        default: return Color.secondary.opacity(0.22)
        }
    }
    private var textColor: Color { rank <= 3 ? .white : .secondary }

    var body: some View {
        Text("\(rank)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(textColor)
            .frame(width: 30, height: 30)
            .background(fill, in: Circle())
    }
}

struct MetaChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

/// The honesty badge (§11). `estimatedLabel` lets each screen name its own guess: the menu side
/// estimated a pour, the store side took a brand's typical label ABV.
struct ProvenanceChip: View {
    let isEstimated: Bool
    var estimatedLabel: String = "estimated"
    var readLabel: String = "from menu"

    private var color: Color { isEstimated ? .orange : .green }

    var body: some View {
        Text(isEstimated ? estimatedLabel : readLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The real, never-fabricated price (§10), with a caption naming where it came from.
struct PricePill: View {
    let dollars: Double
    let caption: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(ValueFormat.money(dollars))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
