//
//  BrandCatalog.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//

import CoreModel

/// A known beverage surfaced to the UI, mainly for the store calculator's brand picker: choosing one
/// pre-fills its category and typical ABV so the shopper only enters size, count, and price. This is
/// a **public projection** of the internal generated brand table (`generatedBrandTable`), so
/// `AppTarget` can build a dropdown without reaching into the lookup internals.
public struct KnownBeverage: Equatable, Sendable, Identifiable {
    public let label: String
    public let category: BeverageCategory
    public let abv: Double
    public var id: String { label }

    public init(label: String, category: BeverageCategory, abv: Double) {
        self.label = label
        self.category = category
        self.abv = abv
    }
}

public enum BrandCatalog {
    /// Every known brand, de-duplicated by display label and sorted alphabetically — ready for a
    /// picker. Computed once. Ordering here is for presentation only; the matcher still uses the
    /// generated table's own most-specific-first ordering.
    public static let all: [KnownBeverage] = {
        var seen = Set<String>()
        var out: [KnownBeverage] = []
        for entry in generatedBrandTable where seen.insert(entry.label).inserted {
            out.append(KnownBeverage(label: entry.label, category: entry.category, abv: entry.abv))
        }
        return out.sorted { $0.label < $1.label }
    }()
}
