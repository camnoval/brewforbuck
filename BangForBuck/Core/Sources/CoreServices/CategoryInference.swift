//
//  CategoryInference.swift
//  Core
//
//  Created by Noval, Cameron on 9/27/26.
//


import CoreModel

/// Give the page's own category to items that ended up with none.
///
/// A menu with no section header leaves every item that didn't brand-match at `.unknown`, and
/// `.unknown`'s default pour is a generic 6 oz. On the rectified ROTATING tap list — a page that is
/// nothing but draft beer — that put four real beers at the bottom of the ranking:
///
///     #18  PLATFORM MARTIAN    8.6% ABV   6 oz   $9    0.10 / $
///     #19  EVERGRAIN JOOSE     6.0% ABV   6 oz   $7    0.09 / $
///     #20  PLATFORM HAZE JUDE  6.0% ABV   6 oz   $8    0.07 / $
///
/// Platform Martian at 8.6% and $9 belongs near the top; it was last because the app assumed a
/// six-ounce pour for a beer it simply didn't recognize. Meanwhile sixteen items on the same page
/// *were* classified, twelve of them beer, by brand match alone. The page had already told us what
/// it was.
///
/// **The rule.** When a clear majority of the classified items agree, unclassified items inherit
/// that category. Nothing else is touched — a classified item keeps what the parser gave it, and
/// `.nonAlcoholic` is never inherited, because "most of this page is beer" is not a reason to call
/// an unknown line beer-strength if the page is actually a soft-drinks list; that one has to be
/// read, not inferred.
///
/// **Why a majority and not a plurality.** A plurality would let a four-beer, three-wine,
/// three-cocktail page impose beer on everything unrecognized, which is a guess dressed as
/// knowledge. A majority means the inference only fires on pages with an evident single subject —
/// a tap list, a wine list, a cocktail list — which is exactly where the section header was
/// missing rather than absent. Requiring a floor of classified items stops a two-item page from
/// deciding anything.
///
/// It stays an estimate: the category only changes the assumed pour, `SizeEstimator` still marks
/// the size estimated, and the UI still says so.
public enum CategoryInference {

    /// Classified items needed before the page is allowed to speak for its unknowns.
    static let minimumClassified = 4

    /// Share of classified items that must agree.
    static let requiredMajority = 0.5

    public static func applyingPageCategory(to items: [MenuItem]) -> [MenuItem] {
        guard let inferred = pageCategory(of: items) else { return items }
        return items.map { item in
            item.category == .unknown ? item.withCategory(inferred) : item
        }
    }

    /// The category a majority of classified items share, or `nil` if the page doesn't have one.
    static func pageCategory(of items: [MenuItem]) -> BeverageCategory? {
        var counts: [BeverageCategory: Int] = [:]
        var classified = 0
        for item in items where item.category != .unknown {
            classified += 1
            counts[item.category, default: 0] += 1
        }
        guard classified >= minimumClassified else { return nil }

        var winner: BeverageCategory?
        var best = 0
        for (category, count) in counts where count > best {
            best = count
            winner = category
        }
        guard let winner, winner != .nonAlcoholic,
              Double(best) / Double(classified) > requiredMajority
        else { return nil }
        return winner
    }
}