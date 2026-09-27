import CoreModel

/// Read a garbled name against the brand table by **glyph shape** instead of by spelling.
///
/// The 09-27 dump is full of names no lookup could match, every one of them a shape confusion away
/// from a brand already in `generatedBrandTable`:
///
///     MICHELOS ULTRA      →  Michelob Ultra          (S for B)
///     BUSCHUGHT           →  Busch Light             (LI read as a single U, space lost)
///     DOGRSH HEAD 60 MIN  →  Dogfish Head 60 Minute  (FI read as a single R)
///     TRUEY WILD BERRY    →  Truly                   (L for E)
///     GUINESS             →  Guinness                (dropped letter)
///
/// A name that doesn't match a brand falls through to the style chart or a category default, which
/// is exactly how a page of printed ABVs ends up ranked on estimates. Lexicon-constrained
/// correction is the standard answer in OCR pipelines, and the lexicon is already in the binary:
/// 655 curated brands, with vetted ABVs and categories.
///
/// **Two folds, then a bounded edit distance.**
///  - *Single-glyph classes* for characters OCR routinely swaps: `0/O/Q`, `1/I/l/|`, `5/S/$`,
///    `8/B`, `6/G`, `2/Z`.
///  - *Ligature collapses*, where two tightly-kerned capitals are read as one glyph: `LI→U`,
///    `FI→R`, `RN→M`, `VV→W`, `CL→D`. These are the ones that make a name unrecognizable rather
///    than merely misspelled, and they are why `BUSCHUGHT` and `Busch Light` fold to the same
///    string — distance zero, no fuzziness needed.
///
/// **Matching is per word, not per character**, which is what keeps it honest. A free-floating
/// character window matches `press` inside `MARG UNDER PRESSURE` and `beck's` inside
/// `BUCKSHORT`; aligning to word boundaries does not. Three relations are allowed:
///
///  1. the brand's words appear in the menu name (`TWISTED TEA SE` → Twisted Tea);
///  2. the menu name is a shorter form of the brand's words, covering at least half of it and at
///     least two words (`DOGRSH HEAD 60 MIN` → Dogfish Head 60 Minute);
///  3. one menu word approximately equals the brand's words run together, for when OCR loses a
///     space (`BUSCHUGHT` → Busch Light).
///
/// **Tolerances scale with length** — no edits allowed on a word under 5 characters, one under 9,
/// two above; total budget one edit under 12 characters of brand, two under 20, three above. A word
/// may be truncated only at the *tail* of a multi-word brand (`60 MIN` for `60 Minute`), because
/// that is where abbreviation actually happens; allowing it anywhere turns `HOUSE RED` into Redd's
/// and `BUD LIGHT` into Budweiser.
///
/// Measured against the real dump: 15 of 15 garbled names repaired, and 0 false positives across 27
/// lines that are not brands (cocktails, wines, styles, towers, ingredient lists, and beers absent
/// from the table).
///
/// **What it deliberately does not do.** `SREWDOG ELVIS AF` stays unmatched. The nearest entry is
/// Brewdog Elvis Juice at 6.5%, but Elvis AF is the alcohol-free one — so a confident partial match
/// would be worse than no match. When the table lacks a beer, the fix is the table, not a looser
/// threshold. Same for `IC UGHT`: `ic light` is simply not in `Tooling/Data/beverages.json` yet.
enum OCRNameRepair {

    /// Best brand entry for a name OCR probably mangled, or `nil` to leave it to the style chart.
    static func match(for name: String) -> BrandEntry? {
        let menu = tokens(of: name)
        guard !menu.isEmpty else { return nil }

        var best: BrandEntry?
        var bestKey: (Int, Int, Int)?

        func offer(_ entry: BrandEntry, _ key: (Int, Int, Int)) {
            if let current = bestKey, !(key < current) { return }
            best = entry
            bestKey = key
        }

        for folded in foldedBrands {
            let brand = folded.tokens
            let chars = folded.characterCount
            guard chars >= 5 else { continue }          // a 4-character brand is too short to risk
            let budget = totalBudget(chars)
            let multiword = brand.count > 1

            if brand.count <= menu.count {
                // 1. The brand's words appear inside the menu name.
                for start in 0...(menu.count - brand.count) {
                    if let total = windowDistance(menu: Array(menu[start..<(start + brand.count)]),
                                                  brand: brand, multiword: multiword),
                       total <= budget {
                        offer(folded.entry, (total, 0, -chars))
                    }
                }
            } else if menu.count >= 2 {
                // 2. The menu name is a shorter form of the brand. Two words minimum, because one
                //    word is a style ("Prosecco" must keep reaching the chart, not become a
                //    specific bottling), and it must cover at least half the brand.
                for start in 0...(brand.count - menu.count) {
                    let window = Array(brand[start..<(start + menu.count)])
                    let covered = window.reduce(0) { $0 + $1.count }
                    guard Double(covered) / Double(chars) >= 0.5 else { continue }
                    if let total = windowDistance(menu: menu, brand: window, multiword: multiword),
                       total <= budget {
                        offer(folded.entry, (total, 1, chars))
                    }
                }
            }

            // 3. OCR lost a space, so one menu word spans the whole brand.
            for word in menu where abs(word.count - folded.joined.count) <= 2 {
                let distance = editDistance(word, folded.joined)
                if distance <= 2, distance <= budget {
                    offer(folded.entry, (distance, 2, -chars))
                }
            }
        }
        return best
    }

    // MARK: - Word alignment

    /// Total edits to read `menu` as `brand`, word for word, or `nil` if any word is too far off.
    private static func windowDistance(menu: [[Character]], brand: [[Character]], multiword: Bool) -> Int? {
        var total = 0
        for index in menu.indices {
            guard let distance = wordDistance(menu[index], brand[index],
                                              isLast: index == menu.count - 1,
                                              multiword: multiword)
            else { return nil }
            total += distance
        }
        return total
    }

    private static func wordDistance(
        _ menu: [Character],
        _ brand: [Character],
        isLast: Bool,
        multiword: Bool
    ) -> Int? {
        if menu == brand { return 0 }
        // A tail word may be an abbreviation: "60 MIN" for "60 Minute". Only at the tail, and only
        // for a multi-word brand — otherwise "BUD" reads as Budweiser and "RED" as Redd's.
        if isLast, multiword, menu.count >= 3, brand.count > menu.count,
           Array(brand.prefix(menu.count)) == menu {
            return 0
        }
        let distance = editDistance(menu, brand)
        return distance <= wordBudget(max(menu.count, brand.count)) ? distance : nil
    }

    /// Edits allowed within one word of `length` characters.
    private static func wordBudget(_ length: Int) -> Int {
        if length < 5 { return 0 }
        if length < 9 { return 1 }
        return 2
    }

    /// Edits allowed across a whole brand of `characters` characters.
    private static func totalBudget(_ characters: Int) -> Int {
        if characters < 12 { return 1 }
        if characters < 20 { return 2 }
        return 3
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1,
                                 current[j - 1] + 1,
                                 previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: - Glyph folding

    /// Two capitals that OCR reads as one glyph. Applied before the single-character classes, and
    /// in this order, because they are what make a name unreadable rather than merely misspelled.
    static let ligatures: [(pair: [Character], replacement: Character)] = [
        (["l", "i"], "u"), (["f", "i"], "r"), (["r", "n"], "m"),
        (["v", "v"], "w"), (["c", "l"], "d"), (["i", "i"], "u"),
    ]

    /// Characters OCR routinely swaps for one another, folded to a single representative.
    static func classFold(_ c: Character) -> Character {
        switch c {
        case "0", "q": return "o"
        case "1", "l", "|", "!": return "i"
        case "5", "$": return "s"
        case "8": return "b"
        case "6": return "g"
        case "2": return "z"
        default: return c
        }
    }

    static func fold(word: String) -> [Character] {
        var letters: [Character] = []
        for c in word.lowercased() where c.isLetter || c.isNumber {
            letters.append(c)
        }
        // Ligature collapses, left to right.
        for (pair, replacement) in ligatures {
            var collapsed: [Character] = []
            var index = 0
            while index < letters.count {
                if index + 1 < letters.count, letters[index] == pair[0], letters[index + 1] == pair[1] {
                    collapsed.append(replacement)
                    index += 2
                } else {
                    collapsed.append(letters[index])
                    index += 1
                }
            }
            letters = collapsed
        }
        return letters.map(classFold)
    }

    static func tokens(of name: String) -> [[Character]] {
        var out: [[Character]] = []
        var word = ""
        func flush() {
            let folded = fold(word: word)
            if !folded.isEmpty, folded != ["a", "n", "d"] { out.append(folded) }
            word = ""
        }
        for c in name {
            if c == " " || c == "-" || c == "/" || c == "\t" || c == "\n" { flush() } else { word.append(c) }
        }
        flush()
        return out
    }

    // MARK: - The folded lexicon, built once

    struct FoldedBrand {
        let tokens: [[Character]]
        let joined: [Character]
        let characterCount: Int
        let entry: BrandEntry
    }

    /// 655 entries, folded at first use. Scanning them per drink name is a few hundred short
    /// edit-distance computations — well inside a menu scan's budget.
    static let foldedBrands: [FoldedBrand] = generatedBrandTable.map { entry in
        let tokens = OCRNameRepair.tokens(of: entry.key)
        return FoldedBrand(tokens: tokens,
                           joined: tokens.flatMap { $0 },
                           characterCount: tokens.reduce(0) { $0 + $1.count },
                           entry: entry)
    }
}
