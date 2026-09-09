//
//  ValueChips.swift
//  ABV
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

    static let millilitersPerOunce = 29.5735

    /// Bottle sizes the trade states in metric. A wine bottle is 750 mL, never 25.4 oz; a handle is
    /// 1.75 L, never 59.2 oz. Printing those in ounces is technically true and reads as wrong.
    static let metricSizes: [Double] = [50, 100, 187, 200, 250, 330, 375, 500, 700, 720, 750,
                                        1000, 1500, 1750, 3000, 5000]

    /// The size as the trade states it: metric for bottle sizes, ounces for everything else. A
    /// 750 mL wine reads "750 mL", a 1.75 L handle reads "1.75 L", a 16 oz can stays "16 oz", and a
    /// 5 oz pour stays "5 oz", which is how a bar states a pour.
    ///
    /// Detection is by volume, not by category, because a *bottle* of wine is metric while a
    /// *glass* of the same wine is a 5 oz pour, and only the volume tells them apart.
    ///
    /// A clean whole number of ounces always wins. Without that guard a 60 oz pitcher reads as
    /// "1.75 L" (1,774 mL is within tolerance of 1,750) and a 24 oz can as "700 mL". No real metric
    /// bottle size lands on a whole ounce, so the two rules never fight.
    static func volume(_ fluidOunces: Double) -> String {
        let rounded = fluidOunces.rounded()
        if abs(fluidOunces - rounded) < 0.05 { return ounces(fluidOunces) }

        let milliliters = fluidOunces * millilitersPerOunce
        for size in metricSizes where abs(milliliters - size) <= size * 0.015 {
            return metric(size)
        }
        return ounces(fluidOunces)
    }

    /// True when `volume(_:)` would print this size in metric, so an input field can label itself.
    static func isMetricSize(_ fluidOunces: Double) -> Bool {
        let rounded = fluidOunces.rounded()
        if abs(fluidOunces - rounded) < 0.05 { return false }
        let milliliters = fluidOunces * millilitersPerOunce
        return metricSizes.contains { abs(milliliters - $0) <= $0 * 0.015 }
    }

    /// Millilitres under a litre, litres at or above it.
    static func metric(_ milliliters: Double) -> String {
        guard milliliters >= 1000 else { return "\(Int(milliliters.rounded())) mL" }
        let liters = milliliters / 1000
        let whole = liters.rounded()
        return abs(liters - whole) < 0.01 ? "\(Int(whole)) L" : String(format: "%g L", liters)
    }

    /// "12 × 12 oz" for a pack, or the container's own size when the count is 1.
    static func package(count: Int, unitOunces: Double) -> String {
        count > 1 ? "\(count) × \(volume(unitOunces))" : volume(unitOunces)
    }

    /// The whole package, kept in the unit the container was stated in, so six 750 mL bottles read
    /// "4.5 L" rather than "152.2 oz".
    static func totalVolume(unitOunces: Double, count: Int) -> String {
        let total = unitOunces * Double(max(1, count))
        return isMetricSize(unitOunces) ? metric(total * millilitersPerOunce) : ounces(total)
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
            Image(systemName: systemImage).font(.system(size: 11))
            Text(title)
        }
        .font(Theme.label)
        .foregroundStyle(Theme.inkMuted)
        .textCase(nil)
    }
}

// MARK: - Small components

/// Gold / silver / bronze for the top three, muted for the rest. A podium is the right metaphor:
/// the person wants a winner, and the metals say the order at a glance without reading a number.
///
/// The metals are what pushed the **value figure** to bottle green rather than amber — gold beside
/// amber muddies both, and amber has one job now (marking an estimate).
struct RankMedal: View {
    let rank: Int

    private var fill: Color {
        switch rank {
        case 1: return Theme.gold
        case 2: return Theme.silver
        case 3: return Theme.bronze
        default: return Theme.wash(Theme.inkMuted)
        }
    }
    private var textColor: Color { rank <= 3 ? .white : Theme.inkMuted }

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 15, weight: .bold, design: .rounded))
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
            .font(Theme.micro)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.wash(Theme.inkMuted), in: Capsule())
            .foregroundStyle(Theme.inkMuted)
            .lineLimit(1)
            .fixedSize()
    }
}

/// The honesty badge (§11). `estimatedLabel` lets each screen name its own guess: the menu side
/// estimated a pour, the store side took a brand's typical label ABV.
struct ProvenanceChip: View {
    let isEstimated: Bool
    var estimatedLabel: String = "estimated"
    var readLabel: String = "from menu"

    /// Amber for a guess, bottle green for something actually printed on the menu. The pairing is
    /// the palette's own liquid-and-glass, so the honesty badge reads as part of the product rather
    /// than a warning bolted on.
    private var color: Color { isEstimated ? Theme.amber : Theme.glass }

    var body: some View {
        Text(isEstimated ? estimatedLabel : readLabel)
            .font(Theme.micro)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Theme.wash(color), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()   // never abbreviate the §11 badge
    }
}

/// The real, never-fabricated price (§10), with a caption naming where it came from.
struct PricePill: View {
    let dollars: Double
    let caption: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(ValueFormat.money(dollars))
                .font(Theme.figureSmall)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(Theme.micro)
                .foregroundStyle(Theme.inkMuted)
        }
    }
}
