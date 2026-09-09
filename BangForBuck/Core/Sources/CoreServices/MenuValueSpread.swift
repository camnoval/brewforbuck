//
//  MenuValueSpread.swift
//  Core
//
//  Created by Noval, Cameron on 9/9/26.
//


import CoreModel

/// The gap between the best and worst value on one menu, as a plain multiple.
///
/// This is the number the supporter prompt uses to say what the app just did, and the share card
/// will use it too. It exists as its own type because it is the one statistic about a ranking that
/// is worth stating in words.
///
/// **Deliberately dimensionless.** A ratio of two values under the same metric carries no currency
/// and no units, so it is safe to say to anyone in any storefront. Multiplying a tier price by a
/// drinks-per-dollar rate is not: the tier is priced in the customer's App Store currency and the
/// menu was priced in whatever the venue printed, and dividing one by the other produces a
/// confident wrong answer. §10 in spirit: do not state a figure the inputs cannot support.
public struct MenuValueSpread: Equatable, Sendable {

    /// The metric value of the best-ranked drink.
    public let bestValue: Double

    /// The metric value of the worst-ranked drink.
    public let worstValue: Double

    /// How many times better the best option is than the worst. Always at least 1.0.
    ///
    /// 1.0 means every priced drink on the menu is the same value, which happens on short menus and
    /// is a perfectly honest answer. It just isn't worth bragging about; see
    /// `SupporterPrompt.minimumRatioWorthMentioning`.
    public let ratio: Double

    public init(bestValue: Double, worstValue: Double, ratio: Double) {
        self.bestValue = bestValue
        self.worstValue = worstValue
        self.ratio = ratio
    }

    /// Build a spread from metric values **already in ranked order, best first**.
    ///
    /// Taking them pre-sorted is what keeps this free of any `higherIsBetter` reasoning: whoever
    /// ranked the list already resolved the metric's direction, so position 0 is the best by
    /// definition and this type never has to know which way the metric points.
    ///
    /// Returns `nil` when there is nothing meaningful to compare:
    /// - fewer than two priced drinks, because one drink is not a comparison
    /// - a worst value of zero or below, because the ratio would be undefined or negative
    public static func of(rankedValues values: [Double]) -> MenuValueSpread? {
        guard values.count >= 2 else { return nil }

        let best = values[0]
        let worst = values[values.count - 1]

        guard worst > 0, best > 0 else { return nil }

        return MenuValueSpread(bestValue: best, worstValue: worst, ratio: best / worst)
    }
}

public extension MenuSession {

    /// The best-to-worst value gap across this session's priced drinks, or `nil` when there are
    /// fewer than two to compare.
    var valueSpread: MenuValueSpread? {
        MenuValueSpread.of(rankedValues: rankedDrinks.map(\.value))
    }
}
