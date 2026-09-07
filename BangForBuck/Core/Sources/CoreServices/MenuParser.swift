import CoreModel

/// Turns OCR text lines into `[MenuItem]` (§7). A small **section-state machine** (Change A): it
/// tracks the current section (category + any header price) so items under a header-priced section
/// like Rullo's "Elixirs | $14" inherit that price. Lines with no price and no header price become
/// `needsPrice` items (price = nil); ingredient/description lines are attached to the item above
/// rather than mistaken for priceless drinks (Finding 4).
///
/// Pure and Foundation-free (hand-rolled scanning, no regex) so the whole thing is fixture-testable.
/// This is deliberately bounded v1 (R1: OCR is *assist* — the manual add/edit path is the safety
/// net): it handles the common shapes seen across real menus, not every possible layout.
public struct MenuParser {
    public init() {}

    /// `trace`, when non-nil, reports which gate consumed each line — the half of the pipeline the
    /// OCR dump can't show, since this loop discards lines at eight different points and a drop is
    /// otherwise indistinguishable from an OCR miss. Emitted from inside the real loop rather than a
    /// reimplementation of it, so it can't drift from what actually happened. Default nil leaves the
    /// shipping path behaviourally identical and allocation-free.
    public func parse(_ lines: [String], trace: ((String) -> Void)? = nil) -> [MenuItem] {
        var items: [MenuItem] = []
        var category: BeverageCategory = .unknown
        var headerPrice: Price? = nil
        var inFoodSection = false   // a "FOOD"/"KITCHEN"/… header drops items until the next drink section
        // Index of the just-emitted priceless, rankable name that a *following* bare-price line should
        // back-fill (the "NAME \n glass $14 | pitcher $49" cocktail layout). Cleared by a section
        // header or once a priced item is emitted, so a price never leaks across a section or item.
        var backfillIndex: Int? = nil

        for raw in lines {
            let line = Self.trimmed(raw)
            if line.isEmpty { continue }

            // Food is dropped entirely (not even shown for review): a food-section header starts a
            // drop region; any drink-section header ends it.
            if Self.isFoodSectionHeader(line) {
                trace?("DROP  food-section-header      | \(line)")
                inFoodSection = true; backfillIndex = nil; continue
            }

            if let (cat, hp) = Self.sectionHeader(line) {
                trace?("SECT  cat=\(cat.rawValue) headerPrice=\(hp.map { "$\($0.dollars)" } ?? "-") | \(line)")
                inFoodSection = false
                // A pure wine sub-label ("whites"/"reds"/"bubbles") groups within the Wine section
                // rather than starting a new one, so it must NOT reset the shared "glass $14 | bottle
                // $58" price the wines under it inherit.
                let isWineSubLabel = cat == .wineGlass && category == .wineGlass && hp == nil
                    && Self.isWineSubLabel(line)
                category = cat
                if !isWineSubLabel { headerPrice = hp }
                backfillIndex = nil     // a new section — don't back-fill across it
                continue
            }

            // Drop food dishes (in a food section, or a stray dish line) and URLs/emails outright —
            // these are never drinks, so they don't belong in the ranking or the "Not sure" bucket.
            // Split into three checks purely so the trace can name which one fired; the condition is
            // the same as the original `inFoodSection || looksLikeFood || looksLikeURL`.
            if inFoodSection {
                trace?("DROP  inside-food-section      | \(line)")
                continue
            }
            if Self.looksLikeFood(line) {
                trace?("DROP  looks-like-food          | \(line)")
                continue
            }
            if Self.looksLikeURL(line) {
                trace?("DROP  looks-like-url           | \(line)")
                continue
            }

            // Non-alcoholic markers on the raw line (N/A, "non-alcoholic", "zero proof") force the
            // category so a brand/style match downstream can't rank e.g. "Gruvi IPA N/A beer" as a
            // real IPA. Checked on the raw line so the "/" in "N/A" is still intact.
            let itemCategory = Self.looksNonAlcoholic(raw) ? .nonAlcoholic : category

            // A nameless size/price grid ("16oz $7 | 22oz $12 | Pitcher $25", or a cocktail's
            // "glass $14 | pitcher $49"). Two layouts, distinguished by whether a name is waiting:
            //   • back-fill — the price line *follows* its drink's name (cocktails). Attach the
            //     smallest (single-serving) price to that just-emitted priceless name.
            //   • forward — the grid *leads* a list of drinks that each carry no price (DRAFTS, a
            //     happy-hour block). Adopt the smallest as the section price the drinks below inherit.
            // The grid line itself is always dropped.
            if let gridPrice = Self.barePriceGridSmallest(line) {
                if let bi = backfillIndex, items[bi].price == nil {
                    trace?("GRID  backfill $\(gridPrice.dollars) onto \"\(items[bi].name)\" | \(line)")
                    items[bi] = items[bi].withPrice(gridPrice)
                    backfillIndex = nil
                } else {
                    trace?("GRID  forward headerPrice=$\(gridPrice.dollars) | \(line)")
                    headerPrice = gridPrice
                }
                continue
            }

            // A line listing several size/price pairs (wine glass/bottle, a beer size grid) becomes
            // one item per size, each ranked separately (Decision: one row per size). Each entry
            // carries its own price, so none fall through to the needsPrice path below.
            let multi = Self.splitMultiPrice(line)
            if !multi.isEmpty {
                // Mirrors the per-entry rank-eligibility suppression applied in the loop below, so
                // the trace shows the price actually stored rather than the one detected.
                trace?("MULTI \(multi.count) entries: "
                    + multi.map { entry in
                        let kept = Self.isRankableName(entry.name)
                        return "\"\(entry.name)\"@" + (kept ? "$\(entry.price.dollars)" : "nil(not-rankable)")
                    }.joined(separator: " / ")
                    + " | \(line)")
                let abv = Self.detectABV(line)   // ABV is usually printed once for the whole line
                for entry in multi {
                    items.append(MenuItem(
                        name: entry.name,
                        price: Self.isRankableName(entry.name) ? entry.price : nil,
                        readABV: abv, readSize: entry.size,
                        category: itemCategory, descriptionText: nil
                    ))
                }
                backfillIndex = nil
                continue
            }

            let parsed = Self.parseItem(line)
            let price = parsed.price ?? headerPrice

            if parsed.price == nil && headerPrice == nil && Self.looksLikeDescription(line) && !items.isEmpty {
                trace?("DESC  attached to \"\(items[items.count - 1].name)\" | \(line)")
                items[items.count - 1] = items[items.count - 1].addingDescription(line)
                continue
            }

            guard !parsed.name.isEmpty else {
                trace?("DROP  empty-name-after-clean   | \(line)")
                continue
            }
            // A price only counts if the name looks like a real drink title; otherwise the line is a
            // recipe/promo/fragment and drops (price suppressed) into the visible needsPrice bucket.
            let rankable = Self.isRankableName(parsed.name)
            let priceIfConfident = rankable ? price : nil
            trace?("ITEM  \(rankable ? "rankable    " : "NOT-RANKABLE")"
                + " name=\"\(parsed.name)\""
                + " price=\(priceIfConfident.map { "$\($0.dollars)" } ?? "nil")"
                + (parsed.price == nil && price != nil ? "(inherited)" : "")
                + " cat=\(itemCategory.rawValue)"
                + " readABV=\(parsed.readABV.map { "\($0)%" } ?? "-")"
                + " readSize=\(parsed.readSize.map { "\($0.fluidOunces)oz" } ?? "-")"
                + " | \(line)")
            items.append(MenuItem(
                name: parsed.name, price: priceIfConfident,
                readABV: parsed.readABV, readSize: parsed.readSize,
                category: itemCategory, descriptionText: nil
            ))
            // Eligible for back-fill only if it's a real drink name still waiting for its price.
            backfillIndex = (priceIfConfident == nil && rankable) ? items.count - 1 : nil
        }
        return items
    }

    // MARK: - Section headers

    /// `(category, headerPrice?)` if the line is a section header, else nil.
    static func sectionHeader(_ line: String) -> (BeverageCategory, Price?)? {
        let lower = line.lowercased()
        let parsed = parseItem(line)
        let hasPipe = contains(line, "|")
        let hasDotLeader = hasDotLeaderRun(line)   // "COCKTAILS........$13" — a dotted section total
        // A priced line is an item, never a header — UNLESS a pipe ("Elixirs | $14"), dot leaders
        // ("COCKTAILS...$13"), or the line is nothing but a section label plus a price ("SHOTS 4",
        // "SHOTS $6 each") mark it as a section total whose items inherit the price.
        if parsed.price != nil && !hasPipe && !hasDotLeader && !isPureSectionLabel(line) { return nil }
        for (keywords, cat) in headerKeywords {
            if keywords.contains(where: { contains(lower, $0) }) {
                return (cat, parsed.price)   // header price (e.g. "Elixirs | $14") when present
            }
        }
        return nil
    }

    /// True if the line contains a run of 2+ consecutive '.' (dot leaders), as printed between a
    /// section name and its price: "COCKTAILS........$13". A single '.' (a decimal) doesn't count.
    static func hasDotLeaderRun(_ s: String) -> Bool {
        let chars = Array(s)
        var i = 1
        while i < chars.count {
            if chars[i] == "." && chars[i - 1] == "." { return true }
            i += 1
        }
        return false
    }

    // Plural / multiword keywords chosen to avoid colliding with singular drink names
    // ("shots" header vs a "…Shot" item; "martinis" vs "Mexican Martini"). Ordered by priority.
    static let headerKeywords: [([String], BeverageCategory)] = [
        (["non-alcoholic", "non alcoholic", "mocktails", "booze free", "zero proof"], .nonAlcoholic),
        (["frozen cocktails", "frozen margaritas", "frozen"], .frozenCocktail),
        (["on tap", "on draught", "draught", "draft beers", "draft selections", "draft beer", "on draft", "drafts", "draft"], .draftBeer),
        (["tall boy", "bottled beer", "bottles/cans", "bottles", "imports", "import", "domestic beer", "domestics", "domestic"], .bottledBeer),
        // "cans" is a container, not a style; most canned items brand-match anyway. Weak seltzer/RTD
        // default for anything that doesn't (ABV is usually printed, so this only nudges the size).
        (["hard seltzer", "canned cocktails", "seltzers", "seltzer", "cans"], .seltzer),
        (["ciders", "cider"], .cider),
        (["shots"], .shot),
        (["martinis", "old-fashioneds", "old fashioneds"], .martini),
        (["sangria"], .sangria),
        (["by the glass", "sparkling", "reds", "whites", "rosé", "rosados", "wine"], .wineGlass),
        (["specialty cocktails", "original cocktails", "signature cocktails", "cocktails", "elixirs", "back to basics", "hand-crafted", "hand crafted", "specialty", "signature"], .cocktail),
    ]

    /// True if the line is *only* a section label — every substantive token is a section word,
    /// with nothing left but a price/size or filler ("each", "per"). Lets "SHOTS 4" and
    /// "SHOTS $6 each" read as headers (their price is inherited) instead of ranking as a "$4 drink".
    static func isPureSectionLabel(_ line: String) -> Bool {
        var sawSection = false
        for token in line.split(separator: " ").map(String.init) {
            let w = stripEdgePunctuation(token).lowercased()
            if w.isEmpty { continue }
            if isMeasurementOrPrice(w) || labelFillerWords.contains(w) { continue }
            if sectionWords.contains(w) { sawSection = true; continue }
            return false   // a real, non-section word — this is an item, not a label
        }
        return sawSection
    }

    static let sectionWords: Set<String> = [
        "beer", "beers", "wine", "wines", "drinks", "drink", "menu", "shots", "shot",
        "cocktail", "cocktails", "food", "drafts", "draft", "bottles", "bottle", "cans", "can",
        "cider", "ciders", "seltzer", "seltzers", "domestic", "domestics", "import", "imports",
        "specialty", "signature", "sangria", "martinis", "elixirs", "reds", "whites", "sparkling",
        "mocktails", "spirits", "beverages", "selections", "bubbles", "rosé", "rose", "rosados",
    ]
    static let labelFillerWords: Set<String> = ["each", "ea", "per", "and", "the", "our", "list", "of"]

    /// Wine sub-groupings that appear under a `Wine` header without their own price — they must not
    /// reset the section's shared by-the-glass/bottle price.
    static let wineSubLabels: Set<String> = ["whites", "reds", "rosé", "rose", "bubbles", "sparkling"]
    static func isWineSubLabel(_ line: String) -> Bool {
        var saw = false
        for token in line.split(separator: " ").map(String.init) {
            let w = stripEdgePunctuation(token).lowercased()
            if w.isEmpty { continue }
            if wineSubLabels.contains(w) { saw = true; continue }
            return false
        }
        return saw
    }

    static func isMeasurementOrPrice(_ w: String) -> Bool {
        if w == "|" || w == "-" || w == "/" || w == "&" || w == "$" { return true }
        if w.hasPrefix("+") { return true }
        if pureNumber(w) != nil { return true }
        if w.hasSuffix("oz") || w.hasSuffix("oz.") || w.hasSuffix("%") || w.hasSuffix("ml") { return true }
        if w == "abv" { return true }
        return false
    }

    /// A header that starts a food block ("FOOD", "KITCHEN", "Small Plates", "Shareables"). Every
    /// substantive token must be a food-section word (size adjectives like "small" allowed as filler).
    static func isFoodSectionHeader(_ line: String) -> Bool {
        var sawFood = false
        for token in line.split(separator: " ").map(String.init) {
            let w = stripEdgePunctuation(token).lowercased()
            if w.isEmpty || w == "&" || labelFillerWords.contains(w) || foodSectionFiller.contains(w) { continue }
            if foodSectionWords.contains(w) { sawFood = true; continue }
            return false
        }
        return sawFood
    }

    /// A dish line ("Parmesan Fries $8", "Buffalo Wings", "Chicken Bites"). Exact-token match against
    /// a deliberately drink-SAFE food list — "taco"/"beer" are excluded so the real beer
    /// "Off Color Beer for Tacos" is not dropped.
    static func looksLikeFood(_ line: String) -> Bool {
        for token in line.split(separator: " ").map(String.init) {
            if foodWords.contains(stripEdgePunctuation(token).lowercased()) { return true }
        }
        return false
    }

    /// A URL or email Vision picked up from a footer ("WWW.ELFERRITOATX.COM").
    static func looksLikeURL(_ line: String) -> Bool {
        let l = line.lowercased()
        return contains(l, "www.") || contains(l, ".com") || contains(l, ".net")
            || contains(l, "://") || contains(l, ".org")
    }

    static let foodSectionWords: Set<String> = [
        "food", "foods", "kitchen", "eats", "snacks", "snack", "apps", "appetizer", "appetizers",
        "starter", "starters", "sides", "mains", "entree", "entrees", "plates", "plate", "bites",
        "shareable", "shareables", "munchies", "nibbles",
    ]
    static let foodSectionFiller: Set<String> = ["small", "large", "bar", "hot", "cold", "warm", "shared"]
    /// Drink-SAFE dish words (exact token match). No "taco"/"beer"/"tea"/"cheese" — those collide with
    /// real drink names.
    static let foodWords: Set<String> = [
        "fries", "cheeseburger", "hamburger", "burger", "burgers", "slider", "sliders", "quesadilla",
        "quesadillas", "nachos", "nacho", "mozzarella", "calamari", "dumplings", "hummus", "guacamole",
        "queso", "burrito", "burritos", "flatbread", "wings", "tenders", "tots", "pretzel", "pretzels",
        "wontons", "empanada", "empanadas", "panini", "meatball", "meatballs", "nuggets", "parmesan",
        "chicken", "bites", "poppers",
    ]

    /// Whether a parsed name is a rankable drink, decided by **casing-independent** structure so a
    /// bar that lowercases its menu still ranks (capitalization is deliberately not a signal — real
    /// menus lowercase titles too). A name is rankable unless it's clearly *not* a drink:
    ///   - a **fragment** with no real word ("$10", "16oz") or only size words ("glass", "pitcher");
    ///   - an **imperative/promo** line ("make it spicy", "For $19.95 get…", "add protein…");
    ///   - a **recipe/ingredient** line (≥2 prep words: "fresh strawberry puree lime juice").
    /// A name that fails keeps no price, so it lands in the visible "Not sure" bucket rather than
    /// polluting the ranking — never silently dropped. Identity (brand/style/ABV) is a separate,
    /// downstream concern that only sets the estimated-vs-read badge, not whether a line ranks.
    static func isRankableName(_ name: String) -> Bool {
        let words = name.split(separator: " ")
            .map { stripEdgePunctuation(String($0)).lowercased() }
            .filter { $0.count >= 2 && $0.contains(where: { $0.isLetter })
                      && !isMeasurementOrPrice($0) && !labelFillerWords.contains($0) }
        guard let first = words.first else { return false }             // fragment: no real word
        if words.allSatisfy({ sectionWords.contains($0) }) { return false }  // bare "whites"/"reds"/"beer"
        if words.allSatisfy({ sizeOnlyWords.contains($0) }) { return false }  // "glass", "pitcher"
        if promoLeadWords.contains(first) { return false }              // imperative / promo lead-in
        if words.filter({ recipeWords.contains($0) }).count >= 2 { return false }  // ingredient list
        return true
    }

    static let promoLeadWords: Set<String> = [
        "make", "add", "ask", "get", "for", "with", "sub", "choice", "choose", "upgrade",
        "any", "all", "includes", "served", "half", "free", "your",
    ]
    /// Words that name a serving vessel, never a drink — a name made only of these is a stray price row.
    static let sizeOnlyWords: Set<String> = [
        "glass", "gloss", "bottle", "pitcher", "pitchor", "carafe", "flight", "pint", "mug", "can", "draft",
        "double", "single", "neat", "rocks", "shot",
    ]
    /// Prep / mixer words that appear in cocktail *recipes*, not titles. Two or more ⇒ ingredient line.
    static let recipeWords: Set<String> = [
        "juice", "syrup", "simple", "fresh", "squeezed", "fresh-squeezed", "puree", "nectar", "soda",
        "water", "bitters", "muddled", "topped", "dash", "splash", "garnish", "rim", "twist", "infused",
        "saline", "distilled", "agave", "cranberry", "curacao", "vermouth", "tonic", "peel", "zest",
        "foam", "germain", "chinola", "colombian", "caramelized", "sec", "sugar",
    ]

    static func parseItem(_ raw: String) -> (price: Price?, name: String, readABV: Double?, readSize: Volume?) {
        let readABV = detectABV(raw)
        let readSize = detectSize(raw)

        let line = collapseDotRuns(replaceSeparators(raw))
        var price: Price? = nil
        var namePart = line

        if let dollarIdx = firstIndex(of: "$", in: line) {
            let chars = Array(line)
            let after = String(chars[(dollarIdx + 1)...])
            if let num = normalizedDollars(leadingDigitString(repairPriceDigits(after))) { price = Price(dollars: num) }
            namePart = String(chars[..<dollarIdx])
        } else if let bare = firstBarePriceToken(line) {
            // A bare 4+-digit superscript-cent price printed without a "$" (Guinness "…1025 1325
            // 2825" → $10.25); take the first (single-serving) one and cut it + the rest off the name.
            if let num = normalizedDollars(bare.digits) { price = Price(dollars: num) }
            let tokens = line.split(separator: " ").map(String.init)
            namePart = tokens[0..<bare.index].joined(separator: " ")
        } else {
            let tokens = line.split(separator: " ").map(String.init)
            if let last = tokens.last, let num = pureNumber(last) {
                price = Price(dollars: num)
                namePart = tokens.dropLast().joined(separator: " ")
            }
        }

        // Many menus print "NAME ABV x% — price"; the ABV/size belong on their own axes (captured
        // above as readABV/readSize), not in the displayed name. Strip those fragments so the name
        // reads cleanly ("Coors Light", not "COORS LIGHT 22oz. ABV 4.2%") and brand matching stays
        // clean.
        let name = cleanName(trimTrailingSeparators(trimmed(namePart)))
        return (price, name, readABV, readSize)
    }

    /// Drop `ABV`, a percentage token (`4.2%`, `>.5%`), a size token (`22oz.`, `16oz`), and stray
    /// dashes from a parsed name. Conservative: only removes tokens that are unambiguously one of
    /// those, so real name words are kept.
    static func cleanName(_ name: String) -> String {
        let kept = name.split(separator: " ").map(String.init).filter { token in
            !(isABVWord(token) || isPercentToken(token) || isSizeToken(token) || isDashToken(token))
        }
        return trimTrailingSeparators(kept.joined(separator: " "))
    }

    static func isABVWord(_ t: String) -> Bool { t.lowercased() == "abv" }

    static func isDashToken(_ t: String) -> Bool {
        let dashes: Set<Character> = ["-", "–", "—"]
        return !t.isEmpty && t.allSatisfy { dashes.contains($0) }
    }

    static func isPercentToken(_ t: String) -> Bool {
        var s = Array(t)
        while s.last == "." { s.removeLast() }
        guard s.last == "%" else { return false }
        s.removeLast()
        while s.first == ">" || s.first == "<" { s.removeFirst() }
        guard !s.isEmpty else { return false }
        return s.allSatisfy { $0.isNumber || $0 == "." }
    }

    static func isSizeToken(_ t: String) -> Bool {
        var s = Array(t.lowercased())
        while s.last == "." { s.removeLast() }
        guard s.count >= 3, s[s.count - 2] == "o", s[s.count - 1] == "z" else { return false }
        let core = s[0..<(s.count - 2)]
        return !core.isEmpty && core.allSatisfy { $0.isNumber || $0 == "." }
    }

    /// A no-price line that reads like an ingredient list rather than a drink name (Finding 4).
    static func looksLikeDescription(_ line: String) -> Bool {
        if contains(line, "•") || contains(line, "·") { return true }
        let commas = line.filter { $0 == "," }.count
        if commas >= 2 { return true }
        let words = line.split(separator: " ").count
        return words > 6
    }

    /// Non-alcoholic markers that should exclude an item regardless of any brand/style match
    /// ("Corona N/A", "Gruvi IPA N/A beer", "…Non Alcoholic", "Zero Proof"). Checked on the raw line.
    /// Deliberately does NOT match bare "zero" — "Mike's Zero Sugar" and similar are alcoholic.
    static func looksNonAlcoholic(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        let markers = ["non-alcoholic", "non alcoholic", "n/a", "n/ a", "zero proof", "alcohol free", "alcohol-free"]
        return markers.contains { contains(lower, $0) }
    }

    // MARK: - Multi-price lines (one item per size)

    /// A drink line carrying two or more `$`-prices (e.g. "House Cabernet glass $9 bottle $32" or
    /// "Bud Light 12oz $4 16oz $6 22oz $8") split into one entry per size, so each size ranks on its
    /// own. Returns `[]` when the line has fewer than two `$`-prices — the single-price path then
    /// handles it unchanged. Sizes are bound to the adjacent size token (before or after the price);
    /// a two-price wine line with no size cues falls back to smaller = glass, larger = bottle.
    static func splitMultiPrice(_ raw: String) -> [(name: String, price: Price, size: Volume?)] {
        let line = collapseDotRuns(replaceSeparators(raw))
        let tokens = line.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        let toks = tokens.map { classifyToken($0) }
        let priceIdx = toks.indices.filter { toks[$0].price != nil }
        guard priceIdx.count >= 2 else { return [] }

        // Base name = the word tokens before the first size-or-price marker.
        let firstMarker = toks.indices.first { toks[$0].price != nil || toks[$0].size != nil } ?? toks.count
        let base = trimTrailingSeparators(trimmed(
            (0..<firstMarker).filter { toks[$0].price == nil && toks[$0].size == nil }
                .map { tokens[$0] }.joined(separator: " ")
        ))
        guard !base.isEmpty else { return [] }   // nameless (size-first) → let single-price path try

        // Bind each price to an adjacent, not-yet-used size token: nearest before, else nearest after.
        var usedSize = Set<Int>()
        var raws: [(price: Double, size: Double?, label: String?)] = []
        for (pi, idx) in priceIdx.enumerated() {
            let prev = pi > 0 ? priceIdx[pi - 1] : -1
            let next = pi < priceIdx.count - 1 ? priceIdx[pi + 1] : toks.count
            var sIdx: Int? = nil
            var k = idx - 1
            while k > prev { if toks[k].size != nil && !usedSize.contains(k) { sIdx = k; break }; k -= 1 }
            if sIdx == nil {
                var m = idx + 1
                while m < next { if toks[m].size != nil && !usedSize.contains(m) { sIdx = m; break }; m += 1 }
            }
            if let s = sIdx { usedSize.insert(s) }
            raws.append((price: toks[idx].price!,
                         size: sIdx.flatMap { toks[$0].size },
                         label: sIdx.flatMap { toks[$0].label }))
        }

        // Wine fallback: exactly two prices, no size cues → smaller is a glass, larger a bottle.
        if raws.count == 2, raws[0].size == nil, raws[1].size == nil {
            let lo = raws[0].price <= raws[1].price ? 0 : 1
            let hi = 1 - lo
            raws[lo] = (price: raws[lo].price, size: 5.0, label: "glass")
            raws[hi] = (price: raws[hi].price, size: 25.36, label: "bottle")
        }

        // Materialize; a non-positive price can't form a Price, so that entry is dropped (invariant).
        var out: [(name: String, price: Price, size: Volume?)] = []
        for r in raws {
            guard let price = Price(dollars: r.price) else { continue }
            let name = r.label.map { "\(base) (\($0))" } ?? base
            out.append((name: name, price: price, size: r.size.map { Volume(fluidOunces: $0) }))
        }
        return out.count >= 2 ? out : []   // still multi only if >=2 survived
    }

    /// 750 mL bottle = 25.36 oz; 1.5 L magnum = 50.72 oz; pitcher ~ 60 oz; carafe ~ 500 mL = 17 oz.
    static let sizeWordTable: [(word: String, ounces: Double)] = [
        ("glass", 5), ("gls", 5), ("gloss", 5), ("bottle", 25.36), ("btl", 25.36), ("bot", 25.36),
        ("pint", 16), ("draft", 16), ("draught", 16), ("pour", 5),
        ("pitcher", 60), ("pitchor", 60), ("carafe", 17), ("half", 8), ("can", 12), ("magnum", 50.72),
    ]

    /// Classify one token as a price (`$9`), a size (`12oz`, `glass`), or a plain word.
    static func classifyToken(_ token: String) -> (price: Double?, size: Double?, label: String?) {
        if let n = dollarValue(token), n > 0 {
            return (n, nil, nil)
        }
        let cleaned = stripEdgePunctuation(token)
        let lower = cleaned.lowercased()
        if lower.count >= 3, lower.hasSuffix("oz") {
            let head = String(lower.dropLast(2))
            if let v = Double(head), v > 0 {
                let label = v == v.rounded() ? "\(Int(v)) oz" : "\(v) oz"
                return (nil, v, label)
            }
        }
        for entry in sizeWordTable where lower == entry.word { return (nil, entry.ounces, entry.word) }
        return (nil, nil, nil)
    }

    static func stripEdgePunctuation(_ s: String) -> String {
        let punct: Set<Character> = [".", ",", "|", ":", ";", "-", "–", "—", "(", ")", "/"]
        var chars = Array(s)
        while let f = chars.first, punct.contains(f) { chars.removeFirst() }
        while let l = chars.last, punct.contains(l) { chars.removeLast() }
        return String(chars)
    }

    // MARK: - Scanners (Foundation-free)

    static func detectABV(_ raw: String) -> Double? {
        let chars = Array(raw)
        for i in chars.indices where chars[i] == "%" {
            var j = i - 1
            var digits = ""
            while j >= 0, chars[j].isNumber || chars[j] == "." { digits = String(chars[j]) + digits; j -= 1 }
            if let v = Double(digits), v > 0, v <= 100 { return v }
        }
        return nil
    }

    static func detectSize(_ raw: String) -> Volume? {
        let lower = raw.lowercased()
        let chars = Array(lower)
        if let i = indexOfSubstring(chars, Array("oz")) {
            var j = i - 1
            while j >= 0, chars[j] == " " { j -= 1 }
            var digits = ""
            while j >= 0, chars[j].isNumber || chars[j] == "." { digits = String(chars[j]) + digits; j -= 1 }
            if let v = Double(digits), v > 0 { return Volume(fluidOunces: v) }
        }
        if contains(lower, "pint") { return Volume(fluidOunces: 16) }
        return nil
    }

    // MARK: - Small string helpers (Foundation-free)

    static func trimmed(_ s: String) -> String {
        let ws: Set<Character> = [" ", "\t", "\n", "\r"]
        let chars = Array(s)
        var start = 0, end = chars.count
        while start < end, ws.contains(chars[start]) { start += 1 }
        while end > start, ws.contains(chars[end - 1]) { end -= 1 }
        return String(chars[start..<end])
    }

    static func trimTrailingSeparators(_ s: String) -> String {
        let seps: Set<Character> = [" ", "-", "–", "—", "|", ":", ",", "•", "·", "."]
        var chars = Array(s)
        while let last = chars.last, seps.contains(last) { chars.removeLast() }
        return String(chars)
    }

    static func replaceSeparators(_ s: String) -> String {
        var out = ""
        for c in s {
            if c == "•" || c == "·" || c == "…" || c == "|" || c == "/" { out.append(" ") } else { out.append(c) }
        }
        return out
    }

    /// Replace runs of 2+ '.' with a space (dot leaders), keeping single '.' (decimals).
    static func collapseDotRuns(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "." {
                var j = i
                while j < chars.count, chars[j] == "." { j += 1 }
                if j - i >= 2 { out.append(" ") } else { out.append(".") }
                i = j
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    static func pureNumber(_ token: String) -> Double? {
        var t = token
        if t.hasPrefix("$") {
            t.removeFirst()
        } else if t.hasPrefix("S") || t.hasPrefix("s") {
            t.removeFirst()   // Vision commonly misreads a "$" as "S" (e.g. "S13" for "$13")
        }
        if t.isEmpty { return nil }
        for c in t where !(c.isNumber || c == ".") { return nil }
        return Double(t)
    }

    static func leadingNumber(_ s: String) -> Double? {
        var digits = ""
        for c in s { if c.isNumber || c == "." { digits.append(c) } else { break } }
        return digits.isEmpty ? nil : Double(digits)
    }

    /// The leading run of digits/decimal-point from the start of `s` (stops at the first other
    /// char), as a raw string so callers can apply superscript-cent normalization.
    static func leadingDigitString(_ s: String) -> String {
        var out = ""
        for c in s { if c.isNumber || c == "." { out.append(c) } else { break } }
        return out
    }

    /// Interpret a run of price digits, tolerating this menu style's superscript cents. A run of 4+
    /// digits with no decimal is read as dollars-and-cents (`1025` → 10.25, `2825` → 28.25, `1055`
    /// → 10.55) — the superscript cents Vision glues onto the dollars. A 1–3 digit run or any run
    /// with an explicit decimal is taken at face value, so a real `$150` bottle stays $150 (a
    /// 3-digit price is genuinely ambiguous; a mispriced pitcher just sinks in the ranking, whereas
    /// halving a real $150 would be a visible error).
    static func normalizedDollars(_ digits: String) -> Double? {
        if digits.isEmpty { return nil }
        if digits.contains(".") { return Double(digits) }
        let chars = Array(digits)
        if chars.count >= 4 {
            let cut = chars.count - 2
            if let d = Double(String(chars[..<cut])), let c = Double(String(chars[cut...])) {
                return d + c / 100
            }
        }
        return Double(digits)
    }

    /// Repair the common OCR letter↔digit confusions inside a price's digit run — a superscript `5`
    /// read as `s`/`S` (`$1s"` → `$15`) and a `0` read as `o`/`O`. Applied only to the characters
    /// after the `$`, so it can't touch a drink name.
    static func repairPriceDigits(_ s: String) -> String {
        String(s.map { c in
            switch c { case "s", "S": return "5"; case "o", "O": return "0"; default: return c }
        })
    }

    /// Dollar value of a price token, tolerating OCR noise: a leading `$`, a `$`→`S`/`s` misread,
    /// glued superscript-cent garble (`$10$5` → 10, `$12"` → 12, `$7.*°` → 7), a superscript `5`
    /// read as `s` (`$1s"` → 15), and 4-digit cents (`$1055` → 10.55). Requires a `$`/`S` prefix — a
    /// bare number is not a price here; bare 4-digit prices are handled only in `firstBarePriceToken`.
    static func dollarValue(_ token: String) -> Double? {
        var body = token
        guard let f = body.first, f == "$" || f == "S" || f == "s" else { return nil }
        body.removeFirst()
        let digits = leadingDigitString(repairPriceDigits(body))
        return digits.isEmpty ? nil : normalizedDollars(digits)
    }

    /// The first whitespace token that is a bare run of 4+ digits — a superscript-cent price printed
    /// without a `$` — as `(tokenIndex, digits)`. Only 4+ digits qualify, so a name's "60" or a "12"
    /// size is never mistaken for a price.
    static func firstBarePriceToken(_ line: String) -> (index: Int, digits: String)? {
        let tokens = line.split(separator: " ").map(String.init)
        for (i, t) in tokens.enumerated() {
            let core = stripEdgePunctuation(t)
            if core.count >= 4, core.allSatisfy({ $0.isNumber }) { return (i, core) }
        }
        return nil
    }

    /// If `line` is only size/price/separator tokens (no real drink-name word) and carries at least
    /// one price, returns its smallest price; otherwise nil. Lets a nameless size/price grid be
    /// adopted as a section-wide price (the smallest = single-serving) that the drinks below inherit.
    static func barePriceGridSmallest(_ line: String) -> Price? {
        let clean = collapseDotRuns(replaceSeparators(line))
        let tokens = clean.split(separator: " ").map(String.init)
        guard tokens.count >= 2 else { return nil }
        let noise: Set<Character> = [".", ",", "|", ":", ";", "-", "–", "—", "(", ")", "/", "\"", "*", "°", "'", "•", "·"]
        var prices: [Double] = []
        var sawSize = false
        for t in tokens {
            let c = classifyToken(t)
            if let p = c.price { prices.append(p); continue }
            if c.size != nil { sawSize = true; continue }
            if t.allSatisfy({ noise.contains($0) }) { continue }   // stray quote/asterisk/degree
            if isMeasurementOrPrice(stripEdgePunctuation(t).lowercased()) { continue }
            return nil   // a real word → this is a named item, not a bare grid
        }
        guard let smallest = prices.min(), sawSize || prices.count >= 2 else { return nil }
        return Price(dollars: smallest)
    }

    static func firstIndex(of ch: Character, in s: String) -> Int? {
        let chars = Array(s)
        for i in chars.indices where chars[i] == ch { return i }
        return nil
    }

    static func lastIndex(of ch: Character, in s: String) -> Int? {
        let chars = Array(s)
        var found: Int? = nil
        for i in chars.indices where chars[i] == ch { found = i }
        return found
    }

    /// Foundation-free substring test.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        indexOfSubstring(Array(haystack), Array(needle)) != nil
    }

    static func indexOfSubstring(_ h: [Character], _ n: [Character]) -> Int? {
        guard !n.isEmpty, n.count <= h.count else { return nil }
        for i in 0...(h.count - n.count) {
            var ok = true
            for j in 0..<n.count where h[i + j] != n[j] { ok = false; break }
            if ok { return i }
        }
        return nil
    }
}

private extension MenuItem {
    func addingDescription(_ text: String) -> MenuItem {
        let combined = descriptionText.map { $0 + " " + text } ?? text
        return MenuItem(name: name, price: price, readABV: readABV, readSize: readSize,
                        category: category, descriptionText: combined)
    }

    /// Same item with a price attached — used to back-fill a cocktail name from the price line that
    /// follows it.
    func withPrice(_ newPrice: Price) -> MenuItem {
        MenuItem(name: name, price: newPrice, readABV: readABV, readSize: readSize,
                 category: category, descriptionText: descriptionText)
    }
}
