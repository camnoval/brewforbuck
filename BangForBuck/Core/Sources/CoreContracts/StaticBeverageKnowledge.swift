import CoreModel

/// The default `BeverageKnowledge` (§6): a pure, sourced lookup that maps a drink name to a typical
/// ABV + pour. Two tiers, per the design you asked for:
///
///   1. **Style chart** — match a beer style / wine varietal keyword in the name and use its typical
///      ABV. Sources: NIAAA (category anchors: beer ~5%, wine ~12%, spirits ~40%), BJCP/craft
///      references for beer styles, and Wine Folly / WSET for wine varietals. See
///      `docs/BeverageDataSources.md` for the full citation list.
///   2. **Category fallback** — when no style matches, use the section's category default and mark
///      the result `.categoryFallback` so the app can say it fell back (§11, R2).
///
/// Pure and Foundation-free, so it lives in Core and is fully unit-testable.
public struct StaticBeverageKnowledge: BeverageKnowledge {
    public init() {}

    public func profile(for name: String, sectionCategory: BeverageCategory?) -> BeverageProfile {
        let key = name.lowercased()

        // Non-alcoholic section wins outright (Change B): don't style-match, don't rank.
        if sectionCategory == .nonAlcoholic {
            return BeverageProfile(category: .nonAlcoholic, typicalABV: 0,
                                   typicalSize: Self.defaultSize(.nonAlcoholic), source: .categoryFallback)
        }

        // 1) Brand table — highest confidence (a specific product). Runs before styles so that,
        //    e.g., "Guinness" resolves to the brand's 4.2% and a non-alcoholic brand (Athletic,
        //    Heineken 0.0) is caught even in a regular beer section (Change B).
        if let brand = generatedBrandTable.first(where: { Self.contains(key, $0.key) }) {
            if brand.category == .nonAlcoholic {
                return BeverageProfile(category: .nonAlcoholic, typicalABV: 0,
                                       typicalSize: Self.defaultSize(.nonAlcoholic),
                                       source: .brandMatch(matched: brand.label))
            }
            let resolved: BeverageCategory = (sectionCategory != nil && sectionCategory != .unknown)
                ? sectionCategory! : brand.category
            return BeverageProfile(category: resolved, typicalABV: brand.abv,
                                   typicalSize: Self.defaultSize(resolved),
                                   source: .brandMatch(matched: brand.label))
        }

        // 1b) Brand table again, this time by glyph shape rather than spelling. A name OCR mangled
        //     ("MICHELOS ULTRA", "BUSCHUGHT", "DOGRSH HEAD 60 MIN") would otherwise fall through to
        //     a style or category estimate, which is how a menu that prints an ABV beside every tap
        //     ends up ranked entirely on guesses. Runs after the exact tier, so a clean name's
        //     behaviour is untouched, and before styles, so a repaired brand still beats a chart
        //     average. The note says which brand it landed on, so the person can see and reject it.
        if let brand = OCRNameRepair.match(for: key) {
            if brand.category == .nonAlcoholic {
                return BeverageProfile(category: .nonAlcoholic, typicalABV: 0,
                                       typicalSize: Self.defaultSize(.nonAlcoholic),
                                       source: .brandMatch(matched: brand.label))
            }
            let resolved: BeverageCategory = (sectionCategory != nil && sectionCategory != .unknown)
                ? sectionCategory! : brand.category
            return BeverageProfile(category: resolved, typicalABV: brand.abv,
                                   typicalSize: Self.defaultSize(resolved),
                                   source: .brandMatch(matched: brand.label))
        }

        // 2) Style / varietal chart (most specific rule wins — the list is ordered that way).
        if let rule = Self.styleRules.first(where: { r in r.keywords.contains { Self.contains(key, $0) } }) {
            let resolved: BeverageCategory = {
                if let s = sectionCategory, s != .unknown { return s }   // section refines size/category
                return rule.natural
            }()
            let size = rule.size ?? Self.defaultSize(resolved)
            return BeverageProfile(category: resolved, typicalABV: rule.abv,
                                   typicalSize: size, source: .styleChart(matched: rule.label))
        }

        // 3) Category fallback (flagged as such).
        if let category = sectionCategory, category != .unknown {
            return BeverageProfile(category: category, typicalABV: Self.defaultABV(category),
                                   typicalSize: Self.defaultSize(category), source: .categoryFallback)
        }

        // 4) Nothing matched at all — generic estimate, lowest confidence.
        return BeverageProfile(category: .unknown, typicalABV: Self.defaultABV(.unknown),
                               typicalSize: Self.defaultSize(.unknown), source: .unclassifiedFallback)
    }

    // MARK: - Category fallback defaults
    // Anchored on NIAAA's standard-drink figures; cocktail/martini/frozen chosen so a typical serving
    // lands near one standard drink, which is the honest default for a mixed drink (R2).

    static func defaultABV(_ c: BeverageCategory) -> Double {
        switch c {
        case .draftBeer, .bottledBeer, .cider, .seltzer: return 5.0
        case .wineGlass:      return 12.0
        case .sangria:        return 10.0
        case .cocktail:       return 12.0   // ~5 oz × 12% ≈ 1 standard drink
        case .frozenCocktail: return 10.0
        case .martini:        return 25.0   // spirit-forward
        case .shot:           return 40.0   // NIAAA spirits
        case .nonAlcoholic:   return 0.0
        case .unknown:        return 12.0
        }
    }

    static func defaultSize(_ c: BeverageCategory) -> Volume {
        switch c {
        case .draftBeer:      return Volume(fluidOunces: 16)   // US pint
        case .bottledBeer, .cider, .seltzer, .nonAlcoholic: return Volume(fluidOunces: 12)
        case .wineGlass:      return Volume(fluidOunces: 5)    // NIAAA wine pour
        case .sangria:        return Volume(fluidOunces: 6)
        case .cocktail:       return Volume(fluidOunces: 5)
        case .frozenCocktail: return Volume(fluidOunces: 8)
        case .martini:        return Volume(fluidOunces: 3.5)
        case .shot:           return Volume(fluidOunces: 1.5)  // NIAAA shot
        case .unknown:        return Volume(fluidOunces: 6)
        }
    }

    // MARK: - Style chart

    private struct Rule {
        let keywords: [String]
        let label: String
        let natural: BeverageCategory
        let abv: Double
        var size: Volume? = nil
    }

    // Ordered most-specific → most-general so `first(where:)` picks the tightest match.
    // ABV values are typical midpoints from the sources cited in docs/BeverageDataSources.md.
    private static let styleRules: [Rule] = [
        // --- Beer / ale styles ---
        Rule(keywords: ["double ipa", "dipa", "imperial ipa"], label: "double IPA", natural: .draftBeer, abv: 8.5),
        Rule(keywords: ["session ipa"], label: "session IPA", natural: .draftBeer, abv: 4.5),
        Rule(keywords: ["ipa"], label: "IPA", natural: .draftBeer, abv: 6.5),
        Rule(keywords: ["imperial stout", "russian imperial"], label: "imperial stout", natural: .draftBeer, abv: 9.0),
        Rule(keywords: ["milk stout", "sweet stout", "oatmeal stout"], label: "sweet stout", natural: .draftBeer, abv: 5.5),
        Rule(keywords: ["dry stout", "irish stout", "guinness"], label: "Irish stout", natural: .draftBeer, abv: 4.2),
        Rule(keywords: ["stout"], label: "stout", natural: .draftBeer, abv: 6.0),
        Rule(keywords: ["baltic porter"], label: "Baltic porter", natural: .draftBeer, abv: 8.0),
        Rule(keywords: ["porter"], label: "porter", natural: .draftBeer, abv: 5.5),
        Rule(keywords: ["hefeweizen", "hefe", "weizen", "weiss", "witbier", "white ale", "wheat"], label: "wheat/witbier", natural: .draftBeer, abv: 5.4),
        Rule(keywords: ["pale ale", "apa"], label: "pale ale", natural: .draftBeer, abv: 5.5),
        Rule(keywords: ["pilsner", "pils", "pilsener"], label: "pilsner", natural: .draftBeer, abv: 4.7),
        Rule(keywords: ["vienna", "marzen", "märzen", "oktoberfest", "amber"], label: "amber/Vienna", natural: .draftBeer, abv: 5.2),
        Rule(keywords: ["blonde", "golden ale", "kolsch", "kölsch", "cream ale"], label: "blonde/golden ale", natural: .draftBeer, abv: 4.8),
        Rule(keywords: ["mexican lager", "modelo", "corona", "pacifico", "dos equis", "tecate"], label: "Mexican lager", natural: .bottledBeer, abv: 4.5),
        Rule(keywords: ["light lager", "light"], label: "light lager", natural: .bottledBeer, abv: 4.2),
        Rule(keywords: ["barleywine", "doppelbock", "tripel", "quadrupel", "quad", "eisbock"], label: "strong ale", natural: .draftBeer, abv: 9.5),
        Rule(keywords: ["bock"], label: "bock", natural: .draftBeer, abv: 6.5),
        Rule(keywords: ["lager"], label: "lager", natural: .draftBeer, abv: 5.0),
        Rule(keywords: ["cider"], label: "cider", natural: .cider, abv: 5.0),
        Rule(keywords: ["sour", "gose"], label: "sour", natural: .draftBeer, abv: 5.0),
        Rule(keywords: ["ale"], label: "ale", natural: .draftBeer, abv: 5.5),
        // --- Hard seltzer / FMB ---
        Rule(keywords: ["seltzer", "white claw", "high noon", "truly", "nutrl", "surfside", "carbliss", "vizzy"], label: "hard seltzer", natural: .seltzer, abv: 5.0),
        // --- Wine varietals ---
        Rule(keywords: ["moscato", "muscat"], label: "Moscato", natural: .wineGlass, abv: 6.0),
        Rule(keywords: ["riesling"], label: "Riesling", natural: .wineGlass, abv: 10.0),
        Rule(keywords: ["prosecco"], label: "Prosecco", natural: .wineGlass, abv: 11.0),
        Rule(keywords: ["champagne", "cava", "sparkling", "brut", "blanc de blanc"], label: "sparkling", natural: .wineGlass, abv: 12.0),
        Rule(keywords: ["pinot grigio", "pinot gris"], label: "Pinot Grigio", natural: .wineGlass, abv: 12.0),
        Rule(keywords: ["sauvignon blanc", "sauv blanc", "sancerre"], label: "Sauvignon Blanc", natural: .wineGlass, abv: 13.0),
        Rule(keywords: ["rose", "rosé", "rosado"], label: "rosé", natural: .wineGlass, abv: 12.5),
        Rule(keywords: ["chardonnay", "chard"], label: "Chardonnay", natural: .wineGlass, abv: 13.5),
        Rule(keywords: ["pinot noir"], label: "Pinot Noir", natural: .wineGlass, abv: 13.5),
        Rule(keywords: ["merlot"], label: "Merlot", natural: .wineGlass, abv: 13.5),
        Rule(keywords: ["cabernet", "cab sauv"], label: "Cabernet", natural: .wineGlass, abv: 14.0),
        Rule(keywords: ["malbec"], label: "Malbec", natural: .wineGlass, abv: 14.0),
        Rule(keywords: ["syrah", "shiraz"], label: "Syrah/Shiraz", natural: .wineGlass, abv: 14.5),
        Rule(keywords: ["zinfandel", "zin"], label: "Zinfandel", natural: .wineGlass, abv: 15.0),
        Rule(keywords: ["port", "sherry", "madeira", "marsala"], label: "fortified wine", natural: .wineGlass, abv: 18.0, size: Volume(fluidOunces: 3.5)),
        Rule(keywords: ["vermouth"], label: "vermouth", natural: .wineGlass, abv: 18.0, size: Volume(fluidOunces: 3.5)),
        Rule(keywords: ["red blend", "red wine"], label: "red wine", natural: .wineGlass, abv: 13.5),
        Rule(keywords: ["white wine"], label: "white wine", natural: .wineGlass, abv: 12.5),
        // --- Sangria (wine + spirit + fruit) ---
        Rule(keywords: ["sangria"], label: "sangria", natural: .sangria, abv: 10.0),
    ]

    /// Foundation-free substring match (case handled by the caller lowercasing `haystack`).
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
