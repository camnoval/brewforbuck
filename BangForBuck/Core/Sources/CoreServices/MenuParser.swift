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

    public func parse(_ lines: [String]) -> [MenuItem] {
        var items: [MenuItem] = []
        var category: BeverageCategory = .unknown
        var headerPrice: Price? = nil

        for raw in lines {
            let line = Self.trimmed(raw)
            if line.isEmpty { continue }

            if let (cat, hp) = Self.sectionHeader(line) {
                category = cat
                headerPrice = hp
                continue
            }

            // Non-alcoholic markers on the raw line (N/A, "non-alcoholic", "zero proof") force the
            // category so a brand/style match downstream can't rank e.g. "Gruvi IPA N/A beer" as a
            // real IPA. Checked on the raw line so the "/" in "N/A" is still intact.
            let itemCategory = Self.looksNonAlcoholic(raw) ? .nonAlcoholic : category

            // A line listing several size/price pairs (wine glass/bottle, a beer size grid) becomes
            // one item per size, each ranked separately (Decision: one row per size). Each entry
            // carries its own price, so none fall through to the needsPrice path below.
            let multi = Self.splitMultiPrice(line)
            if !multi.isEmpty {
                let abv = Self.detectABV(line)   // ABV is usually printed once for the whole line
                for entry in multi {
                    items.append(MenuItem(
                        name: entry.name, price: entry.price,
                        readABV: abv, readSize: entry.size,
                        category: itemCategory, descriptionText: nil
                    ))
                }
                continue
            }

            let parsed = Self.parseItem(line)
            let price = parsed.price ?? headerPrice

            if parsed.price == nil && headerPrice == nil && Self.looksLikeDescription(line) && !items.isEmpty {
                items[items.count - 1] = items[items.count - 1].addingDescription(line)
                continue
            }

            guard !parsed.name.isEmpty else { continue }
            items.append(MenuItem(
                name: parsed.name, price: price,
                readABV: parsed.readABV, readSize: parsed.readSize,
                category: itemCategory, descriptionText: nil
            ))
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
        // A priced line is an item, never a header — UNLESS a pipe ("Elixirs | $14") or dot leaders
        // ("COCKTAILS...$13") mark it as a section total whose items inherit the price.
        if parsed.price != nil && !hasPipe && !hasDotLeader { return nil }
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

    // MARK: - Item parsing

    static func parseItem(_ raw: String) -> (price: Price?, name: String, readABV: Double?, readSize: Volume?) {
        let readABV = detectABV(raw)
        let readSize = detectSize(raw)

        let line = collapseDotRuns(replaceSeparators(raw))
        var price: Price? = nil
        var namePart = line

        if let dollarIdx = lastIndex(of: "$", in: line) {
            let chars = Array(line)
            let after = String(chars[(dollarIdx + 1)...])
            if let num = leadingNumber(after) { price = Price(dollars: num) }
            namePart = String(chars[..<dollarIdx])
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
        ("glass", 5), ("gls", 5), ("bottle", 25.36), ("btl", 25.36), ("bot", 25.36),
        ("pint", 16), ("draft", 16), ("draught", 16), ("pour", 5),
        ("pitcher", 60), ("carafe", 17), ("half", 8), ("can", 12), ("magnum", 50.72),
    ]

    /// Classify one token as a price (`$9`), a size (`12oz`, `glass`), or a plain word.
    static func classifyToken(_ token: String) -> (price: Double?, size: Double?, label: String?) {
        if token.hasPrefix("$"), let n = pureNumber(String(token.dropFirst())), n > 0 {
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
        if t.hasPrefix("$") { t.removeFirst() }
        if t.isEmpty { return nil }
        for c in t where !(c.isNumber || c == ".") { return nil }
        return Double(t)
    }

    static func leadingNumber(_ s: String) -> Double? {
        var digits = ""
        for c in s { if c.isNumber || c == "." { digits.append(c) } else { break } }
        return digits.isEmpty ? nil : Double(digits)
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
}
