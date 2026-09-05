//
//  PackageDefaults.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel

/// A starting container and pack count for a product the shopper just picked. Always editable in
/// the form; the point is that the common cases need no editing at all.
public struct PackageSuggestion: Equatable, Sendable {
    public let container: ContainerSize
    public let count: Int

    public init(container: ContainerSize, count: Int) {
        self.container = container
        self.count = count
    }
}

/// Guess the package shape so the shopper doesn't set it by hand every time: a wine opens at
/// 750 mL, a Coors at a 12 oz six-pack, a handle of vodka at 1.75 L. Pure and Foundation-free, so
/// every rule below is a one-line test rather than something you discover on device.
///
/// Three sources, most trustworthy first:
/// 1. **What the catalog said.** A stated size or pack count is a fact and always wins.
/// 2. **What the name says.** Store names carry the package: "Coors Light 16oz 12pk",
///    "Tito's 1.75L", "Josh Cellars Cabernet 750ml". Reading it is free and usually exact.
/// 3. **What the category implies.** The fallback, and the only genuinely *guessed* tier.
///
/// This is presentation-adjacent but it is not presentation: it's a rule set with real edge cases
/// ("30 rack", a spirits "pint" being 375 mL and not 16 oz), which is exactly the kind of thing that
/// belongs in tested pure code rather than in a SwiftUI view (§7).
public enum PackageDefaults {

    public static func suggest(
        name: String,
        category: BeverageCategory,
        containerMilliliters: Double? = nil,
        unitsPerPackage: Int? = nil
    ) -> PackageSuggestion {
        let lowered = name.lowercased()

        let container: ContainerSize
        if let milliliters = containerMilliliters, milliliters > 0 {
            container = ContainerSize.closest(toMilliliters: milliliters)
        } else if let fromName = containerFromName(lowered, category: category) {
            container = fromName
        } else {
            container = defaultContainer(for: category)
        }

        let count = unitsPerPackage ?? countFromName(lowered) ?? defaultCount(for: category, container: container)

        return PackageSuggestion(container: container, count: max(1, count))
    }

    // MARK: - Tier 2: read the package off the name

    /// Sizes are matched as whole *tokens* after units are glued to their number, never as loose
    /// substrings. That distinction matters: a substring search for "200" finds it inside the
    /// vintage in "Josh Cellars 2007 Cabernet" and would size a bottle of wine at 200 mL. Token
    /// matching on a unit-normalized name ("1.75 L" and "1.75L" both become the token `1.75l`) can't
    /// make that mistake, and a bare number is only accepted when it stands alone as its own word.
    static func containerFromName(_ lowered: String, category: BeverageCategory) -> ContainerSize? {
        let normalized = normalizedForSizes(lowered)
        let tokens = words(normalized).map(stripTrailingDots)
        let tokenSet = Set(tokens)

        // 1. Trade words that name a size without stating a number. The short ones are matched as
        //    whole words, not substrings: "handle" is inside the real winery "Handley Cellars", and
        //    "nip" is inside the real wine "Nipozzano", so a substring test mis-sizes both.
        if tokenSet.contains("handle") || contains(lowered, "half gallon") { return .liter175 }
        if tokenSet.contains("magnum") { return .liter15 }
        if tokenSet.contains("stovepipe") { return .can192 }
        if tokenSet.contains("tallboy") || containsAny(lowered, ["tall boy", "pounder"]) { return .can16 }
        if tokenSet.contains("fifth") { return .ml750 }
        if tokenSet.contains("nip") || tokenSet.contains("mini") { return .ml50 }

        // 2. Any number with a unit glued to it. Generic on purpose: enumerating sizes misses the
        //    real ones (a 14.9 oz Guinness can, an 11.2 oz Euro bottle, a 5 L box), and a shopper
        //    entering an unlisted size by hand is exactly the friction this is meant to remove.
        for token in tokens {
            if let ounces = number(in: token, unit: "oz") { return .closest(toFluidOunces: ounces) }
            if let milliliters = number(in: token, unit: "ml") { return .closest(toMilliliters: milliliters) }
            if let liters = number(in: token, unit: "l") { return .closest(toMilliliters: liters * 1000) }
        }

        // 3. A bare number, accepted only when it stands alone as a word AND is a real bottle size.
        //    This is the weakest tier: a substring search would read the vintage in "2007 Cabernet"
        //    as 200 mL, and even as a token a number is thinner evidence than a number with a unit.
        let bareBottleSizes: [String: Double] = [
            "50": 50, "187": 187, "200": 200, "375": 375, "500": 500,
            "750": 750, "1000": 1000, "1500": 1500, "1750": 1750,
        ]
        for token in tokens {
            if let milliliters = bareBottleSizes[token] { return .closest(toMilliliters: milliliters) }
        }

        // 4. A spirits "pint" is 375 mL and a "half pint" 200 mL, nothing like a beer pint. Only
        //    trust the word inside a spirits category, or it would mis-size a pint of cider.
        if isSpirituous(category) {
            if contains(lowered, "half pint") { return .ml200 }
            if tokenSet.contains("pint") { return .ml375 }
        }

        return nil
    }

    /// The numeric part of a token like "14.9oz", or `nil` if the token isn't that unit. Requires
    /// the unit to be the whole remainder, so "12pk" is never read as 12 of anything measured.
    static func number(in token: String, unit: String) -> Double? {
        let chars = Array(token)
        let unitChars = Array(unit)
        guard chars.count > unitChars.count else { return nil }

        let splitAt = chars.count - unitChars.count
        for i in 0..<unitChars.count where chars[splitAt + i] != unitChars[i] { return nil }

        let digits = String(chars[0..<splitAt])
        guard let value = Double(digits), value > 0 else { return nil }
        return value
    }

    /// Glue a unit onto the number in front of it and spell it canonically, so "1.75 Liter",
    /// "1.75L" and "1.75 l" all normalize to `1.75l`, and "16 OZ" to `16oz`.
    static func normalizedForSizes(_ lowered: String) -> String {
        let chars = Array(lowered)
        var out: [Character] = []
        var index = 0
        while index < chars.count {
            if chars[index] == " ", let previous = out.last, previous.isNumber {
                var cursor = index + 1
                var unit = ""
                while cursor < chars.count, chars[cursor].isLetter {
                    unit.append(chars[cursor])
                    cursor += 1
                }
                if let canonical = PackageDefaults.canonicalUnit(unit) {
                    out.append(contentsOf: canonical)
                    index = cursor
                    continue
                }
            }
            out.append(chars[index])
            index += 1
        }
        return String(out)
    }

    static func canonicalUnit(_ word: String) -> [Character]? {
        switch word {
        case "ml", "mls", "milliliter", "milliliters": return Array("ml")
        case "l", "lt", "ltr", "liter", "liters", "litre", "litres": return Array("l")
        case "oz", "ounce", "ounces", "fl": return Array("oz")
        default: return nil
        }
    }

    /// "1.75l." from a catalog's punctuation becomes "1.75l".
    static func stripTrailingDots(_ token: String) -> String {
        var chars = Array(token)
        while chars.last == "." { chars.removeLast() }
        return String(chars)
    }

    /// Split on anything that isn't a letter, digit, or decimal point, so a decimal size survives.
    static func words(_ s: String) -> [String] {
        var out: [String] = []
        var current: [Character] = []
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "." {
                current.append(ch)
            } else if !current.isEmpty {
                out.append(String(current))
                current = []
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// Pack counts: "12pk", "12 pack", "12-pack", "case", "30 rack". Read as a number immediately
    /// followed by a pack word, so a size like "16oz" can't be read as a count.
    static func countFromName(_ lowered: String) -> Int? {
        if containsAny(lowered, ["30 rack", "30rack", "30-rack"]) { return 30 }

        let chars = Array(lowered)
        var index = 0
        while index < chars.count {
            guard chars[index].isNumber else { index += 1; continue }

            var digits = ""
            var cursor = index
            while cursor < chars.count, chars[cursor].isNumber {
                digits.append(chars[cursor])
                cursor += 1
            }
            // Allow one space or hyphen between the number and the pack word.
            if cursor < chars.count, chars[cursor] == " " || chars[cursor] == "-" { cursor += 1 }

            let rest = String(chars[cursor...])
            if startsWithAny(rest, ["pk", "pack", "pks", "packs", "ct", "count"]),
               let value = Int(digits), value >= 2, value <= 48 {
                return value
            }
            index = cursor
        }

        if containsAny(lowered, ["case of 24", " case"]) { return 24 }
        return nil
    }

    // MARK: - Tier 3: category fallback

    static func defaultContainer(for category: BeverageCategory) -> ContainerSize {
        switch category {
        case .wineGlass, .sangria:
            return .ml750
        case .cocktail, .frozenCocktail, .martini, .shot:
            return .ml750
        case .draftBeer, .bottledBeer, .cider, .seltzer, .nonAlcoholic, .unknown:
            return .can12
        }
    }

    static func defaultCount(for category: BeverageCategory, container: ContainerSize) -> Int {
        // A big bottle is sold on its own whatever the category says.
        if container.volume.milliliters >= 500 { return 1 }

        switch category {
        case .seltzer:
            return 12                       // hard seltzer is a variety pack far more often than not
        case .draftBeer, .bottledBeer, .cider:
            return 6
        case .wineGlass, .sangria, .cocktail, .frozenCocktail, .martini, .shot,
             .nonAlcoholic, .unknown:
            return 1
        }
    }

    static func isSpirituous(_ category: BeverageCategory) -> Bool {
        switch category {
        case .cocktail, .frozenCocktail, .martini, .shot: return true
        default: return false
        }
    }

    // MARK: - Foundation-free helpers

    static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { contains(haystack, $0) }
    }

    static func startsWithAny(_ haystack: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { hasPrefix(haystack, $0) }
    }

    static func hasPrefix(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let h = Array(haystack), n = Array(needle)
        guard n.count <= h.count else { return false }
        for i in 0..<n.count where h[i] != n[i] { return false }
        return true
    }

    static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        let h = Array(haystack), n = Array(needle)
        guard n.count <= h.count else { return false }
        for i in 0...(h.count - n.count) {
            var matched = true
            for j in 0..<n.count where h[i + j] != n[j] { matched = false; break }
            if matched { return true }
        }
        return false
    }
}
