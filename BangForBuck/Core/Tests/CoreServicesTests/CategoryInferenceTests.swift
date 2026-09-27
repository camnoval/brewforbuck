//
//  CategoryInferenceTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/27/26.
//

import XCTest
@testable import CoreServices
import CoreModel

/// A menu with no section header leaves unrecognized items at `.unknown`, whose default pour is a
/// generic 6 oz — which is what buried Platform Martian (8.6% ABV, $9) at #18 of 20 on a page that
/// was nothing but draft beer. These tests pin both halves: the inference fires on a page with an
/// evident single subject, and stays silent on a page that hasn't got one.
final class CategoryInferenceTests: XCTestCase {

    private func item(_ name: String, _ category: BeverageCategory) -> MenuItem {
        MenuItem(name: name, price: Price(dollars: 7), category: category)
    }

    /// The tap list: twelve of sixteen classified items were beer, by brand match alone. The page
    /// had already said what it was.
    func testAPageThatIsPlainlyBeerLendsItsCategoryToWhatItDidNotRecognize() {
        let items = [
            item("Bell's Two Hearted", .draftBeer),
            item("Troegs Dreamweaver", .draftBeer),
            item("Guinness", .draftBeer),
            item("Yuengling", .draftBeer),
            item("Platform Martian", .unknown),
            item("Platform Haze Jude", .unknown),
        ]
        let out = CategoryInference.applyingPageCategory(to: items)
        XCTAssertEqual(out.map(\.category),
                       [.draftBeer, .draftBeer, .draftBeer, .draftBeer, .draftBeer, .draftBeer])
    }

    /// A classified item keeps what the parser gave it. Inference fills holes; it doesn't overrule.
    func testAClassifiedItemIsNeverReclassified() {
        let items = [
            item("Bell's Two Hearted", .draftBeer),
            item("Troegs Dreamweaver", .draftBeer),
            item("Guinness", .draftBeer),
            item("Truly", .seltzer),
            item("Blake's Flannel Mouth", .cider),
        ]
        XCTAssertEqual(CategoryInference.applyingPageCategory(to: items).map(\.category),
                       [.draftBeer, .draftBeer, .draftBeer, .seltzer, .cider])
    }

    /// A plurality is not a majority. On a mixed page, imposing the commonest category on everything
    /// unrecognized would be a guess wearing the clothes of knowledge.
    func testAMixedPageInfersNothing() {
        let items = [
            item("Bell's Two Hearted", .draftBeer),
            item("Troegs Dreamweaver", .draftBeer),
            item("Pinot Noir", .wineGlass),
            item("Prosecco", .wineGlass),
            item("Old Fashioned", .cocktail),
            item("Something Unreadable", .unknown),
        ]
        XCTAssertEqual(CategoryInference.pageCategory(of: items), nil)
        XCTAssertEqual(CategoryInference.applyingPageCategory(to: items).last?.category, .unknown)
    }

    /// Too little evidence to speak for anything.
    func testATinyPageInfersNothing() {
        let items = [item("Bud Light", .draftBeer), item("Mystery", .unknown)]
        XCTAssertEqual(CategoryInference.pageCategory(of: items), nil)
    }

    /// Non-alcoholic is never inherited. "Most of this page is soda" is not grounds for giving an
    /// unreadable line a zero ABV — or for giving it beer strength if the reverse were allowed.
    /// That distinction has to be read off the menu, not inferred from its neighbours.
    func testNonAlcoholicIsNeverInherited() {
        let items = [
            item("Coke", .nonAlcoholic),
            item("Sprite", .nonAlcoholic),
            item("Ginger Ale", .nonAlcoholic),
            item("Lemonade", .nonAlcoholic),
            item("Unreadable", .unknown),
        ]
        XCTAssertEqual(CategoryInference.pageCategory(of: items), nil)
        XCTAssertEqual(CategoryInference.applyingPageCategory(to: items).last?.category, .unknown)
    }

    func testAPageOfOnlyUnknownsInfersNothing() {
        let items = (1...6).map { item("Item \($0)", .unknown) }
        XCTAssertEqual(CategoryInference.pageCategory(of: items), nil)
    }
}
