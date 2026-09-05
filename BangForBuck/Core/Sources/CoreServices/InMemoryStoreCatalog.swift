//
//  InMemoryStoreCatalog.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//


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
/// milliseconds and behaves identically whatever loaded the products (the compiled brand list today,
/// a bundled JSON catalog once the PLCB and Open Food Facts import lands).
///
/// Search is deliberately *ranked*, not filtered. With 655 products a plain substring filter is
/// fine; with tens of thousands, typing "coors" and getting "Coors Banquet" third behind two
/// obscure imports whose description happens to contain the word is the difference between a usable
/// search and an unusable one. The tiers below put an exact name first, then a name that starts with
/// what you typed, then a name where any *word* starts with it, then everything else that matches.
public struct InMemoryStoreCatalog: StoreCatalog {

    /// A product plus its precomputed lowercased name. Lowercasing 30,000 names on every keystroke
    /// is what would make live search feel slow, so it happens once at init instead.
    private struct Indexed: Sendable {
        let product: CatalogProduct
        let lowercasedName: String
    }

    private let indexed: [Indexed]
    private let byUPC: [String: CatalogProduct]

    public var productCount: Int { indexed.count }

    public init(products: [CatalogProduct]) {
        self.indexed = products.map { Indexed(product: $0, lowercasedName: $0.name.lowercased()) }

        var upcMap: [String: CatalogProduct] = [:]
        for product in products {
            if let upc = product.upc, !upc.isEmpty {
                upcMap[InMemoryStoreCatalog.normalizedUPC(upc)] = product
            }
        }
        self.byUPC = upcMap
    }

    // MARK: - StoreCatalog

    public func search(_ query: String, limit: Int = 40) -> [CatalogProduct] {
        let needle = InMemoryStoreCatalog.trimmed(query).lowercased()
        guard !needle.isEmpty else { return [] }

        let tokens = InMemoryStoreCatalog.words(needle)

        var scored: [(product: CatalogProduct, tier: Int, name: String)] = []
        for entry in indexed {
            guard let tier = InMemoryStoreCatalog.tier(
                name: entry.lowercasedName, needle: needle, tokens: tokens
            ) else { continue }
            scored.append((entry.product, tier, entry.lowercasedName))
        }

        scored.sort { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.name < b.name
        }

        return scored.prefix(max(0, limit)).map(\.product)
    }

    public func product(withUPC upc: String) -> CatalogProduct? {
        byUPC[InMemoryStoreCatalog.normalizedUPC(upc)]
    }

    // MARK: - Ranking

    /// Lower is better. `nil` means no match at all.
    /// 0 exact name · 1 name starts with the query · 2 some word starts with the query ·
    /// 3 the query appears somewhere · 4 every typed word appears somewhere, in any order.
    static func tier(name: String, needle: String, tokens: [String]) -> Int? {
        if name == needle { return 0 }
        if hasPrefix(name, needle) { return 1 }
        if words(name).contains(where: { hasPrefix($0, needle) }) { return 2 }
        if contains(name, needle) { return 3 }
        if tokens.count > 1, tokens.allSatisfy({ contains(name, $0) }) { return 4 }
        return nil
    }

    /// A barcode compared digits-only, so a 12-digit UPC-A and its 14-digit GTIN form (which the
    /// PLCB catalogs export with the leading zeros stripped) still find each other.
    static func normalizedUPC(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        var trimmed = Array(digits)
        while trimmed.count > 12, trimmed.first == "0" { trimmed.removeFirst() }
        return String(trimmed)
    }

    // MARK: - Foundation-free string helpers

    static func trimmed(_ s: String) -> String {
        let whitespace: Set<Character> = [" ", "\t", "\n", "\r"]
        var chars = Array(s)
        while let first = chars.first, whitespace.contains(first) { chars.removeFirst() }
        while let last = chars.last, whitespace.contains(last) { chars.removeLast() }
        return String(chars)
    }

    /// Split on anything that isn't a letter, digit, or decimal point, so "Coors Light 16oz" gives
    /// ["coors", "light", "16oz"] and "1.75L" keeps its decimal.
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

public extension InMemoryStoreCatalog {
    /// The catalog the app ships with today: the curated brand list already compiled into
    /// `CoreContracts`. Names and ABVs only, so `PackageDefaults` infers the container and count.
    /// Replaced (not extended) by a bundled catalog once the import script has run.
    static var curatedBrands: InMemoryStoreCatalog {
        InMemoryStoreCatalog(
            products: BrandCatalog.all.map {
                CatalogProduct(name: $0.label, category: $0.category, abv: $0.abv)
            }
        )
    }
}
