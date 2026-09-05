import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// Ranked product search for the store calculator. Ranking is the whole point: with a large catalog
/// a plain substring filter buries the obvious answer under coincidental matches, so these tests pin
/// the tiers rather than just "the result appears somewhere".
final class StoreCatalogSearchTests: XCTestCase {

    private let catalog = InMemoryStoreCatalog(products: [
        CatalogProduct(name: "Coors", category: .bottledBeer, abv: 5.0),
        CatalogProduct(name: "Coors Light", category: .bottledBeer, abv: 4.2),
        CatalogProduct(name: "Coors Banquet", category: .bottledBeer, abv: 5.0),
        CatalogProduct(name: "Keystone Light (by Coors)", category: .bottledBeer, abv: 4.1),
        CatalogProduct(name: "Light Lager Sampler", category: .bottledBeer, abv: 4.5),
        CatalogProduct(name: "Josh Cellars Cabernet Sauvignon",
                       category: .wineGlass, abv: 13.5, containerMilliliters: 750, upc: "083300003001"),
        CatalogProduct(name: "Tito's Handmade Vodka",
                       category: .shot, abv: 40, containerMilliliters: 1750, upc: "619947000020"),
        // Real catalog names, kept because they are what the name folding exists for.
        CatalogProduct(name: "Moët & Chandon - Brut Impérial", category: .wineGlass, abv: 12),
        CatalogProduct(name: "Margaux - Chateau Margaux 2014", category: .wineGlass, abv: 13),
        CatalogProduct(name: "St. Remy - V.S.O.P.", category: .shot, abv: 40),
    ])

    // MARK: - Tiers

    func testExactNameOutranksLongerNamesThatStartWithIt() {
        XCTAssertEqual(catalog.search("coors", limit: 10).first?.name, "Coors")
    }

    func testPrefixMatchesOutrankInteriorMatches() {
        let names = catalog.search("coors", limit: 10).map(\.name)
        // Everything whose name begins with "Coors" comes before the one that merely mentions it.
        let keystoneIndex = names.firstIndex(of: "Keystone Light (by Coors)")!
        for name in ["Coors", "Coors Light", "Coors Banquet"] {
            XCTAssertLessThan(names.firstIndex(of: name)!, keystoneIndex, "\(name) should outrank Keystone")
        }
    }

    /// Typing a later word should still find the product: "light" matches "Coors Light" on a
    /// word-start, which beats "Keystone Light (by Coors)" only by name length, but both rank above
    /// nothing at all.
    func testAWordStartAnywhereInTheNameMatches() {
        let names = catalog.search("light", limit: 10).map(\.name)
        XCTAssertTrue(names.contains("Coors Light"))
        XCTAssertTrue(names.contains("Light Lager Sampler"))
        // "Light Lager Sampler" starts with the query, so it wins the tier above word-start.
        XCTAssertEqual(names.first, "Light Lager Sampler")
    }

    /// Several typed words, in any order, all present somewhere. This is the tier that makes
    /// "vodka titos" work.
    func testAllTypedWordsMatchInAnyOrder() {
        XCTAssertEqual(catalog.search("vodka tito", limit: 5).first?.name, "Tito's Handmade Vodka")
        XCTAssertEqual(catalog.search("cabernet josh", limit: 5).first?.name, "Josh Cellars Cabernet Sauvignon")
    }

    func testShorterNamesBreakTiesSoTheObviousAnswerIsFirst() {
        // All three begin with "Coors", so they share a tier and length decides: the bare brand
        // first, then Light (11 chars), then Banquet (13).
        let names = catalog.search("coors", limit: 10).map(\.name)
        XCTAssertEqual(Array(names.prefix(3)), ["Coors", "Coors Light", "Coors Banquet"])
    }

    // MARK: - Behaviour

    func testEmptyQueryReturnsNothingRatherThanEverything() {
        XCTAssertTrue(catalog.search("", limit: 10).isEmpty)
        XCTAssertTrue(catalog.search("   ", limit: 10).isEmpty)
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(catalog.search("chartreuse", limit: 10).isEmpty)
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(catalog.search("COORS LIGHT", limit: 5).first?.name, "Coors Light")
        XCTAssertEqual(catalog.search("cOoRs LiGhT", limit: 5).first?.name, "Coors Light")
    }

    func testLimitIsRespected() {
        XCTAssertEqual(catalog.search("coors", limit: 2).count, 2)
        XCTAssertTrue(catalog.search("coors", limit: 0).isEmpty)
    }

    func testProductCountReportsTheCatalogSize() {
        XCTAssertEqual(catalog.productCount, 10)
    }

    // MARK: - Name folding
    //
    // Names are matched on a folded form: lowercase, accents stripped, apostrophes and periods
    // deleted, everything else a word break. Without it, a shopper types what's on the shelf tag
    // and the catalog doesn't recognize its own product.

    /// Nobody types the diaeresis in Moët.
    func testAccentsAreIgnored() {
        XCTAssertEqual(catalog.search("moet", limit: 3).first?.name, "Moët & Chandon - Brut Impérial")
        XCTAssertEqual(catalog.search("imperial", limit: 3).first?.name, "Moët & Chandon - Brut Impérial")
        // And typing the accent still works.
        XCTAssertEqual(catalog.search("moët", limit: 3).first?.name, "Moët & Chandon - Brut Impérial")
    }

    /// An apostrophe is deleted rather than treated as a word break, so "titos" matches "Tito's".
    /// Treating it as a break folded the name to "tito s" and this search found nothing.
    func testApostrophesAreIgnoredEitherWay() {
        for query in ["titos", "tito's", "tito", "Tito's Handmade"] {
            XCTAssertEqual(catalog.search(query, limit: 3).first?.name, "Tito's Handmade Vodka",
                           "\(query) should find Tito's")
        }
    }

    /// Periods are deleted, so "V.S.O.P." folds to "vsop"; the space after "St." still breaks.
    func testPeriodsFoldIntoTheWord() {
        XCTAssertEqual(catalog.search("vsop", limit: 3).first?.name, "St. Remy - V.S.O.P.")
        XCTAssertEqual(catalog.search("st remy", limit: 3).first?.name, "St. Remy - V.S.O.P.")
    }

    /// BC names lead with the appellation ("MARGAUX - CHATEAU MARGAUX 2014"), so the separator has
    /// to fold to a plain space or a shopper searching the producer finds nothing.
    func testSeparatorsFoldToSpacesSoTheProducerIsSearchable() {
        XCTAssertEqual(catalog.search("chateau margaux", limit: 3).first?.name,
                       "Margaux - Chateau Margaux 2014")
        XCTAssertEqual(catalog.search("chandon brut", limit: 3).first?.name,
                       "Moët & Chandon - Brut Impérial")
    }

    /// A vintage year is part of the name and stays searchable.
    func testDigitsAreSearchable() {
        XCTAssertEqual(catalog.search("margaux 2014", limit: 3).first?.name,
                       "Margaux - Chateau Margaux 2014")
    }

    // MARK: - Barcode seam

    func testBarcodeLookupIgnoresFormattingAndLeadingZeros() {
        XCTAssertEqual(catalog.product(withUPC: "083300003001")?.name, "Josh Cellars Cabernet Sauvignon")
        // The PLCB catalogs export the 14-digit GTIN with leading zeros stripped; both forms of the
        // same barcode must resolve to the same product.
        XCTAssertEqual(catalog.product(withUPC: "00083300003001")?.name, "Josh Cellars Cabernet Sauvignon")
        XCTAssertEqual(catalog.product(withUPC: "0-83300-00300-1")?.name, "Josh Cellars Cabernet Sauvignon")
        XCTAssertNil(catalog.product(withUPC: "999999999999"))
    }

    func testProductsWithoutBarcodesAreStillSearchable() {
        XCTAssertNil(catalog.search("coors light", limit: 1).first?.upc)
        XCTAssertEqual(catalog.search("coors light", limit: 1).first?.abv, 4.2)
    }

    // MARK: - The catalog shipped today

    func testCuratedBrandCatalogIsSearchable() {
        let curated = InMemoryStoreCatalog.curatedBrands
        XCTAssertGreaterThan(curated.productCount, 600)
        XCTAssertEqual(curated.search("bud light", limit: 5).first?.name, "Bud Light")
        // Curated entries carry an ABV but no size, which is what `PackageDefaults` is for.
        let budLight = curated.search("bud light", limit: 1).first
        XCTAssertNotNil(budLight?.abv)
        XCTAssertNil(budLight?.containerMilliliters)
    }
}
