//
//  InMemoryStoreCatalog.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//

import CoreModel
import CoreContracts

/// A `StoreCatalog` over products already in memory, with ranked name search. Pure and
/// Foundation-free like the rest of `CoreServices`, so the ranking is fixture-testable in
/// milliseconds and behaves identically whatever loaded the products.
///
/// **Everything is precomputed at init**, because this runs on every keystroke over a catalog of
/// ~17,000 products. The first version lowercased and re-split each name inside the query loop,
/// which allocated a fresh array per product per call: roughly 50,000 allocations per typed
/// character, and typing visibly stuttered while the CPU gauge stayed near idle, because the cost
/// was allocation rather than arithmetic. Now each product is stored as a folded byte array with
/// its word boundaries already marked, so a query is pure index comparison with no allocation at
/// all beyond folding the query itself once.
///
/// Search is deliberately *ranked*, not filtered. With this many products a plain substring filter
/// buries the obvious answer under coincidental matches, so the tiers below put an exact name first,
/// then a name starting with what you typed, then a name whose word starts with it, then the rest.
public struct InMemoryStoreCatalog: StoreCatalog {

    /// A product with its search index. `folded` is the name reduced to lowercase ASCII letters,
    /// digits, and single spaces: accents stripped, punctuation collapsed. That folding is what lets
    /// "moet" find "Moët" and "chateau margaux" find "MARGAUX - CHATEAU MARGAUX 2014".
    private struct Indexed {
        let product: CatalogProduct
        let folded: [UInt8]
        /// Byte offsets where a word begins, so the word-prefix tier costs no scanning.
        let wordStarts: [Int32]
    }

    private let indexed: [Indexed]
    private let byUPC: [String: CatalogProduct]

    public var productCount: Int { indexed.count }

    public init(products: [CatalogProduct]) {
        var entries: [Indexed] = []
        entries.reserveCapacity(products.count)
        var upcMap: [String: CatalogProduct] = [:]

        for product in products {
            let folded = InMemoryStoreCatalog.fold(product.name)
            var starts: [Int32] = []
            if !folded.isEmpty {
                starts.append(0)
                for index in 1..<folded.count where folded[index - 1] == 32 {
                    starts.append(Int32(index))
                }
            }
            entries.append(Indexed(product: product, folded: folded, wordStarts: starts))

            if let upc = product.upc, !upc.isEmpty {
                upcMap[InMemoryStoreCatalog.normalizedUPC(upc)] = product
            }
        }

        self.indexed = entries
        self.byUPC = upcMap
    }

    // MARK: - StoreCatalog

    public func search(_ query: String, limit: Int = 40) -> [CatalogProduct] {
        let needle = InMemoryStoreCatalog.fold(query)
        guard !needle.isEmpty, limit > 0 else { return [] }

        let tokens = needle.split(separator: 32).map(Array.init)

        var scored: [(index: Int, tier: UInt8, length: Int)] = []
        scored.reserveCapacity(64)

        for position in indexed.indices {
            if let tier = tier(indexed[position], needle: needle, tokens: tokens) {
                scored.append((position, tier, indexed[position].folded.count))
            }
        }

        scored.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.length != b.length { return a.length < b.length }
            return compareBytes(indexed[a.index].folded, indexed[b.index].folded)
        }

        return scored.prefix(limit).map { indexed[$0.index].product }
    }

    public func product(withUPC upc: String) -> CatalogProduct? {
        byUPC[InMemoryStoreCatalog.normalizedUPC(upc)]
    }

    // MARK: - Ranking

    /// Lower is better. `nil` means no match.
    /// 0 exact name · 1 name starts with the query · 2 some word starts with the query ·
    /// 3 the query appears somewhere · 4 every typed word appears somewhere, in any order.
    private func tier(_ entry: Indexed, needle: [UInt8], tokens: [[UInt8]]) -> UInt8? {
        let name = entry.folded
        // With one typed word, a name shorter than the query can't match any tier. With several,
        // each token is matched separately, so the combined length proves nothing and this fast
        // path would wrongly reject "vodka tito" against a short name.
        if tokens.count <= 1, name.count < needle.count { return nil }
        if name.count == needle.count, name == needle { return 0 }
        if matches(name, needle, at: 0) { return 1 }
        for start in entry.wordStarts where matches(name, needle, at: Int(start)) { return 2 }
        if firstIndex(of: needle, in: name) != nil { return 3 }
        if tokens.count > 1 {
            for token in tokens where firstIndex(of: token, in: name) == nil { return nil }
            return 4
        }
        return nil
    }

    /// Does `needle` sit at exactly `offset` in `name`? Index comparison, no allocation.
    private func matches(_ name: [UInt8], _ needle: [UInt8], at offset: Int) -> Bool {
        guard offset + needle.count <= name.count else { return false }
        for index in 0..<needle.count where name[offset + index] != needle[index] { return false }
        return true
    }

    private func firstIndex(of needle: [UInt8], in name: [UInt8]) -> Int? {
        guard !needle.isEmpty, needle.count <= name.count else { return nil }
        let first = needle[0]
        let last = name.count - needle.count
        var offset = 0
        while offset <= last {
            if name[offset] == first, matches(name, needle, at: offset) { return offset }
            offset += 1
        }
        return nil
    }

    private func compareBytes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        for index in 0..<min(lhs.count, rhs.count) where lhs[index] != rhs[index] {
            return lhs[index] < rhs[index]
        }
        return lhs.count < rhs.count
    }

    // MARK: - Folding

    /// Reduce a name to lowercase ASCII letters, digits, and single spaces. Accented letters fold to
    /// their plain form so "moet" finds "Moët" and "nimes" finds "Nîmes"; everything else
    /// (punctuation, dashes, variation selectors, zero-width joiners) becomes a word break. Applied
    /// to both sides of a comparison, so the two can't disagree.
    static func fold(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(text.count)
        var pendingSpace = false

        for scalar in text.lowercased().unicodeScalars {
            let value = scalar.value
            var mapped: [UInt8] = []

            // Apostrophes and periods are *deleted* rather than turned into a word break, so
            // "Tito's" folds to "titos" (a shopper types it without the apostrophe) and "V.S.O.P."
            // to "vsop". "St. Remy" still folds to "st remy", because the space after the period
            // supplies the break. Every other non-alphanumeric character becomes a break.
            if value == 0x27 || value == 0x2019 || value == 0x2E { continue }

            if value < 128 {
                let byte = UInt8(value)
                if (byte >= 97 && byte <= 122) || (byte >= 48 && byte <= 57) { mapped = [byte] }
            } else {
                mapped = InMemoryStoreCatalog.asciiFold(value)
            }

            if mapped.isEmpty {
                if !out.isEmpty { pendingSpace = true }
            } else {
                if pendingSpace { out.append(32); pendingSpace = false }
                out.append(contentsOf: mapped)
            }
        }
        return out
    }

    /// Latin-1 and Latin Extended-A letters a shopper would type unaccented. Anything unlisted folds
    /// to a word break, which is the right answer for punctuation and invisible characters.
    static func asciiFold(_ value: UInt32) -> [UInt8] {
        switch value {
        case 0xE0...0xE5, 0x101, 0x103, 0x105:            return [97]   // a
        case 0xE7, 0x107, 0x109, 0x10D:                   return [99]   // c
        case 0xE8...0xEB, 0x113, 0x115, 0x117, 0x119, 0x11B: return [101] // e
        case 0xEC...0xEF, 0x12B, 0x12D, 0x12F:            return [105]  // i
        case 0xF1, 0x144, 0x148:                          return [110]  // n
        case 0xF2...0xF6, 0xF8, 0x14D, 0x14F, 0x151:      return [111]  // o
        case 0xF9...0xFC, 0x16B, 0x16D, 0x171, 0x173:     return [117]  // u
        case 0xFD, 0xFF:                                  return [121]  // y
        case 0x161, 0x15B, 0x15F:                         return [115]  // s
        case 0x17E, 0x17A, 0x17C:                         return [122]  // z
        case 0x11F, 0x11D:                                return [103]  // g
        case 0x159, 0x155:                                return [114]  // r
        case 0x165, 0x163:                                return [116]  // t
        case 0x13E, 0x13A, 0x142:                         return [108]  // l
        case 0x10F, 0x10B:                                return [100]  // d
        case 0xE6:                                        return [97, 101]   // ae
        case 0x153:                                       return [111, 101]  // oe
        case 0xDF:                                        return [115, 115]  // ss
        default:                                          return []
        }
    }

    /// The folded name split into words, as strings. Used by `CatalogMatcher` to compare a menu
    /// line against a product name word-for-word, on the same folding the search uses so the two
    /// can't disagree about what a word is.
    static func foldedWords(_ text: String) -> [String] {
        fold(text).split(separator: 32).map { String(decoding: $0) }
    }

    /// A barcode compared digits-only, so a 12-digit UPC-A and its 14-digit GTIN form (which the
    /// PLCB catalogs export with the leading zeros stripped) still find each other.
    static func normalizedUPC(_ raw: String) -> String {
        var digits: [Character] = []
        for character in raw where character.isNumber { digits.append(character) }
        while digits.count > 12, digits.first == "0" { digits.removeFirst() }
        return String(digits)
    }
}

private extension String {
    /// Bytes to `String` without Foundation. The folded form is ASCII by construction, so a direct
    /// scalar mapping is exact.
    init(decoding bytes: ArraySlice<UInt8>) {
        self.init(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
    }
}

public extension InMemoryStoreCatalog {
    /// The fallback catalog: the curated brand list already compiled into `CoreContracts`. Names and
    /// ABVs only, so `PackageDefaults` infers the container and count. Superseded by the bundled
    /// catalog built from the BC and PLCB data once that file is in the app.
    static var curatedBrands: InMemoryStoreCatalog {
        InMemoryStoreCatalog(
            products: BrandCatalog.all.map {
                CatalogProduct(name: $0.label, category: $0.category, abv: $0.abv)
            }
        )
    }
}
