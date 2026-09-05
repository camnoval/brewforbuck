//
//  PourDefaultsTests.swift
//  Core
//
//  Created by Noval, Cameron on 9/5/26.
//


import XCTest
@testable import CoreServices
import CoreContracts
import CoreModel

/// Pour inference for the quick menu comparison. The category tier delegates to
/// `BeverageKnowledge`, so these mostly pin the name-reading tier and the vessel words that mean
/// different volumes in different categories.
final class PourDefaultsTests: XCTestCase {

    private let knowledge = StaticBeverageKnowledge()

    /// How the app actually calls it: profile the name, then let the wording override the profile.
    private func suggest(_ name: String, _ category: BeverageCategory) -> ContainerSize {
        let profile = knowledge.profile(for: name, sectionCategory: category)
        return PourDefaults.suggest(name: name, category: category, typicalSize: profile.typicalSize)
    }

    // MARK: - Category tier, borrowed from BeverageKnowledge

    func testCategoryPoursMatchTheMenuScannersOwnEstimates() {
        XCTAssertEqual(suggest("House Red", .wineGlass), .pour5)
        XCTAssertEqual(suggest("Well Tequila", .shot), .pour15)
        XCTAssertEqual(suggest("Some Lager", .bottledBeer).volume.fluidOunces, 12, accuracy: 0.001)
    }

    /// The pour comes from the same sourced numbers the scanner estimates with, so the two features
    /// can't disagree about what a wine pour is.
    func testPourAgreesWithTheKnowledgeProfile() {
        let profile = knowledge.profile(for: "Pinot Noir", sectionCategory: .wineGlass)
        let pour = PourDefaults.suggest(name: "Pinot Noir", category: .wineGlass,
                                        typicalSize: profile.typicalSize)
        XCTAssertEqual(pour.volume.fluidOunces, profile.typicalSize.fluidOunces, accuracy: 0.5)
    }

    func testNoProfileFallsBackToTwelveOunces() {
        XCTAssertEqual(PourDefaults.suggest(name: "Mystery Drink", category: .unknown), .can12)
    }

    // MARK: - Read it off the menu line

    func testExplicitSizeWins() {
        XCTAssertEqual(suggest("Draft IPA 16 oz", .draftBeer), .can16)
        XCTAssertEqual(suggest("Tall Boy 24oz", .bottledBeer), .can24)
        XCTAssertEqual(suggest("Espresso Martini 5 oz", .martini), .pour5)
    }

    /// An unlisted size keeps its own label rather than snapping to the nearest pour.
    func testUnusualSizeKeepsItsLabel() {
        let guinness = suggest("Guinness 14.9oz", .draftBeer)
        XCTAssertEqual(guinness.volume.fluidOunces, 14.9, accuracy: 0.001)
        XCTAssertEqual(guinness.label, "14.9 oz")
    }

    func testVesselWordsThatNameASizeOutright() {
        XCTAssertEqual(suggest("Margarita Pitcher", .cocktail), .pitcher60)
        XCTAssertEqual(suggest("Whiskey Double", .shot), .pour3)
        XCTAssertEqual(suggest("Fireball Shot", .shot), .pour15)
        XCTAssertEqual(suggest("Guinness Pint", .draftBeer), .can16)
    }

    /// `gloss`/`pitchor` are Vision's misreads of glass/pitcher, already handled in `MenuParser`;
    /// the pour reader accepts the same typo so a scanned line and a typed line agree.
    func testOCRMisreadOfPitcherIsAccepted() {
        XCTAssertEqual(suggest("Paloma pitchor", .cocktail), .pitcher60)
    }

    // MARK: - Vessel words that only mean something in context

    /// A glass of wine is 5 oz. A "glass" of beer is anyone's guess, so the word is ignored there
    /// and the category default stands.
    func testGlassAndBottleOnlyCountForWine() {
        XCTAssertEqual(suggest("Cabernet by the glass", .wineGlass), .pour5)
        XCTAssertEqual(suggest("Cabernet bottle", .wineGlass).volume.fluidOunces, 25.4, accuracy: 0.1)

        // Beer: "bottle" is a 12 oz bottle, not a 25 oz wine bottle.
        XCTAssertEqual(suggest("Bud Light bottle", .draftBeer).volume.fluidOunces, 12, accuracy: 0.001)
    }

    func testDraftMeansAPint() {
        XCTAssertEqual(suggest("Yuengling draft", .draftBeer), .can16)
        XCTAssertEqual(suggest("Yuengling draught", .draftBeer), .can16)
    }

    // MARK: - Presets

    func testPourPresetsAreServingSizedNotPackageSized() {
        XCTAssertFalse(ContainerSize.pourPresets.isEmpty)
        // No handles or half-bottles offered as a single serving.
        XCTAssertFalse(ContainerSize.pourPresets.contains(.liter175))
        XCTAssertFalse(ContainerSize.pourPresets.contains(.ml750))
        XCTAssertTrue(ContainerSize.pourPresets.contains(.pour15))
        XCTAssertTrue(ContainerSize.pourPresets.contains(.pitcher60))
    }

    func testSnappingTargetsTheRequestedList() {
        // 5 oz is a wine pour among pours, and nothing like a preset package size.
        XCTAssertEqual(ContainerSize.closest(toFluidOunces: 5, among: ContainerSize.pourPresets), .pour5)
        XCTAssertEqual(ContainerSize.closest(toFluidOunces: 12), .can12)
    }
}
