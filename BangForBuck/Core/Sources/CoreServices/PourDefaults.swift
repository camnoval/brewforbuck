//
//  PourDefaults.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel
import CoreContracts

/// The single-serving twin of `PackageDefaults`: what pour a menu line most likely means, so the
/// quick comparison opens with a sensible size instead of an empty field.
///
/// Same three-tier shape, most trustworthy source first:
/// 1. **What the line says.** "16 oz", "pitcher", "double", "glass of wine" all name a pour, and a
///    menu says one of these more often than you'd think.
/// 2. **What the category implies**, via `BeverageKnowledge.typicalSize`: the same sourced NIAAA
///    pours the menu scanner already estimates with (12 oz beer, 5 oz wine, 1.5 oz shot). Reusing
///    that means the two features can never disagree about what a wine pour is.
/// 3. **A 12 oz fallback** if there's no profile at all.
///
/// The result is snapped to a pour preset when one is close, so a drinker sees "5 oz wine pour"
/// rather than "5 oz", and keeps its own ounce label when nothing fits.
public enum PourDefaults {

    /// `typicalSize` is what `BeverageKnowledge.profile(for:sectionCategory:)` returned for this
    /// name, or `nil` if no profile was consulted.
    public static func suggest(
        name: String,
        category: BeverageCategory,
        typicalSize: Volume? = nil
    ) -> ContainerSize {
        let lowered = name.lowercased()

        if let fromName = pourFromName(lowered, category: category) {
            return fromName
        }
        if let typicalSize, typicalSize.fluidOunces > 0 {
            return ContainerSize.closest(toFluidOunces: typicalSize.fluidOunces,
                                         among: ContainerSize.pourPresets)
        }
        return .can12
    }

    /// Read a pour off the menu wording. Uses the same unit-normalized token matching as
    /// `PackageDefaults`, so "16 OZ" and "16oz" behave alike and a number can't be mistaken for a
    /// size when it isn't one.
    static func pourFromName(_ lowered: String, category: BeverageCategory) -> ContainerSize? {
        let tokens = PackageDefaults.words(PackageDefaults.normalizedForSizes(lowered))
            .map(PackageDefaults.stripTrailingDots)
        let tokenSet = Set(tokens)

        // Vessels that name a size outright.
        if tokenSet.contains("pitcher") || tokenSet.contains("pitchor") { return .pitcher60 }
        if tokenSet.contains("double") { return .pour3 }
        if tokenSet.contains("shot") || tokenSet.contains("shooter") { return .pour15 }
        if tokenSet.contains("pint") { return .can16 }

        // An explicit size wins over any vessel word.
        for token in tokens {
            if let ounces = PackageDefaults.number(in: token, unit: "oz") {
                return .closest(toFluidOunces: ounces, among: ContainerSize.pourPresets)
            }
            if let milliliters = PackageDefaults.number(in: token, unit: "ml") {
                return .closest(toFluidOunces: Volume(milliliters: milliliters).fluidOunces,
                                among: ContainerSize.pourPresets)
            }
        }

        // "Glass" and "bottle" mean completely different volumes depending on what's in them, so
        // they're only trusted where the category settles it.
        let isWine = category == .wineGlass || category == .sangria
        if isWine {
            if tokenSet.contains("bottle") { return .closest(toFluidOunces: 25.4, among: ContainerSize.pourPresets) }
            if tokenSet.contains("glass") { return .pour5 }
        } else if category == .draftBeer {
            if tokenSet.contains("bottle") || tokenSet.contains("can") { return .can12 }
            if tokenSet.contains("draft") || tokenSet.contains("draught") { return .can16 }
        }

        return nil
    }
}
