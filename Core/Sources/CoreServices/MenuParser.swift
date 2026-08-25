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
                category: category, descriptionText: nil
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
        // A priced line with no pipe is an item, never a header.
        if parsed.price != nil && !hasPipe { return nil }
        for (keywords, cat) in headerKeywords {
            if keywords.contains(where: { contains(lower, $0) }) {
                return (cat, parsed.price)   // header price (e.g. "Elixirs | $14") when present
            }
        }
        return nil
    }

    // Plural / multiword keywords chosen to avoid colliding with singular drink names
    // ("shots" header vs a "…Shot" item; "martinis" vs "Mexican Martini"). Ordered by priority.
    static let headerKeywords: [([String], BeverageCategory)] = [
        (["non-alcoholic", "non alcoholic", "mocktails", "booze free", "zero proof"], .nonAlcoholic),
        (["frozen cocktails", "frozen margaritas", "frozen"], .frozenCocktail),
        (["on tap", "on draught", "draught", "draft beers", "draft selections", "draft beer", "on draft"], .draftBeer),
        (["tall boy", "bottled beer", "bottles/cans", "bottles", "imports", "domestic beer", "domestics"], .bottledBeer),
        (["hard seltzer", "canned cocktails", "seltzers"], .seltzer),
        (["ciders"], .cider),
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

        let name = trimTrailingSeparators(trimmed(namePart))
        return (price, name, readABV, readSize)
    }

    /// A no-price line that reads like an ingredient list rather than a drink name (Finding 4).
    static func looksLikeDescription(_ line: String) -> Bool {
        if contains(line, "•") || contains(line, "·") { return true }
        let commas = line.filter { $0 == "," }.count
        if commas >= 2 { return true }
        let words = line.split(separator: " ").count
        return words > 6
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
        let seps: Set<Character> = [" ", "-", "|", ":", ",", "•", "·", "."]
        var chars = Array(s)
        while let last = chars.last, seps.contains(last) { chars.removeLast() }
        return String(chars)
    }

    static func replaceSeparators(_ s: String) -> String {
        var out = ""
        for c in s {
            if c == "•" || c == "·" || c == "…" || c == "|" { out.append(" ") } else { out.append(c) }
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
