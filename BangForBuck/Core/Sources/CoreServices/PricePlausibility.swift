//
//  PricePlausibility.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//


import CoreModel

/// Withdraw prices that don't fit the rest of *this* menu (§10, §11).
///
/// A misread price is worse than no price: `PABST BLUE RIBBON 1602.` ranks a $3.50
/// beer at $16.02, and `7-Up 415` ranks at $415. Both are real tokens off the page
/// attached to the wrong thing, so the "never fabricate a price" invariant holds
/// while the number shown is still wrong. The fix is to withhold the price and let
/// the item travel the `needsPrice` path, where the person can type the real one.
/// Nothing is ever corrected or guessed.
///
/// **The test is relative, not absolute.** An absolute band would be wrong on the
/// first menu that isn't priced in present-day dollars: the 1948 Roosevelt list
/// prices everything between $0.20 and $1.60, so a `$1` floor would condemn the
/// whole menu while happily passing `$415`. So each price is judged against the
/// other prices *in its own category on the same menu*.
///
/// Three details, each load-bearing on real OCR:
///
///  - **Lower quartile, not median.** On a badly-read menu more than half the
///    prices can be junk — the 1948 list has true prices near $1 and misreads up to
///    $415 — and a median then sits *among the junk* and condemns the real prices.
///    The lower quartile resists contamination from above.
///  - **High side only.** A price far below its peers is usually a genuinely cheap
///    item, or a dropped digit we cannot tell apart from one; withholding it would
///    throw away good data for no gain.
///  - **The multiple is deliberately far out, because expensive drinks are real.**
///    A rare bourbon pour at 6.7x the cheap end of its list, a $120 champagne at
///    13.3x, a 750 mL bottle among cans at 7.5x, pitchers beside pints at 4.3x — all
///    genuine, all common. A tighter rule withdraws them. Measured against those and
///    the real misreads, anything from 16x to 30x catches the egregious cases and
///    touches none of the legitimate ones; 20x sits in the middle of that.
///
/// **What this deliberately does NOT catch.** Misreads inside the plausible range
/// stay: `PABST BLUE RIBBON 1602.` at 4x, `Coca Cola 15` at 15.8x. Reaching them
/// costs real prices, and losing a real price is worse than showing a suspicious
/// one, because the person can see and fix a wrong number but cannot recover a
/// number that was silently withheld. This rule is a backstop for absurdity, not a
/// general price validator.
///
/// **Evidence base, stated plainly:** the rule fires on 2 of the 8 real OCR dumps,
/// so its calibration rests on those two plus a handful of hand-built menus
/// representing shapes the corpus lacks (long-tail spirits, one premium bottle,
/// large formats, pitchers). The 16x-30x plateau is as good as that sample. Anyone
/// adding a menu that trips this should re-run `Tooling/` before touching the number.
public enum PricePlausibility {

    /// A price this many times the category's lower quartile is treated as a misread.
    /// Dimensionless on purpose: every decision is a ratio between prices on the same
    /// menu, so the rule behaves identically whether the menu is priced in dollars,
    /// yen, or 1948 dollars. Verified by scaling every price on all 8 dumps by 0.01,
    /// 0.7, 100 and 1000 — identical decisions each time.
    public static let outlierMultiple = 20.0
    /// Below this many prices in a category there is no evidence to judge against,
    /// so nothing is withdrawn. Silence beats a guess.
    public static let minimumSample = 4

    /// Every item, with implausible prices replaced by `nil` (⇒ `needsPrice`).
    public static func withdrawingImplausiblePrices(_ items: [MenuItem]) -> [MenuItem] {
        let doubted = implausiblePriceIndices(items)
        guard !doubted.isEmpty else { return items }
        return items.enumerated().map { index, item in
            guard doubted.contains(index) else { return item }
            return MenuItem(
                name: item.name,
                price: nil,                       // withheld, never corrected
                readABV: item.readABV,
                readSize: item.readSize,
                category: item.category,
                descriptionText: item.descriptionText
            )
        }
    }

    /// Indices of items whose price doesn't fit its category on this menu.
    public static func implausiblePriceIndices(_ items: [MenuItem]) -> Set<Int> {
        var byCategory: [BeverageCategory: [Int]] = [:]
        for (index, item) in items.enumerated() where item.price != nil {
            byCategory[item.category, default: []].append(index)
        }

        var doubted: Set<Int> = []
        for (_, indices) in byCategory {
            let prices = indices.compactMap { items[$0].price?.dollars }
            guard prices.count >= minimumSample else { continue }
            let reference = lowerQuartile(prices)
            guard reference > 0 else { continue }

            // No second-mode guard is needed at this multiple: wine by the bottle
            // beside wine by the glass measures ~7.7x and pitchers beside pints ~4.3x,
            // both far below the bar.
            let ceiling = outlierMultiple * reference
            for index in indices where (items[index].price?.dollars ?? 0) > ceiling {
                doubted.insert(index)
            }
        }
        return doubted
    }

    /// Median of the lower half — robust to junk piled up at the top.
    public static func lowerQuartile(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let half = sorted.count % 2 == 0
            ? Array(sorted[0..<(sorted.count / 2)])
            : Array(sorted[0...(sorted.count / 2)])
        return median(half)
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}