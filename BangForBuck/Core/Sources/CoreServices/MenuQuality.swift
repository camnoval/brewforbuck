//
//  MenuQuality.swift
//  Core
//
//  Created by Noval, Cameron on 9/7/26.
//


import CoreModel

/// How well a menu was read, so a thin read can be **flagged** rather than trusted silently (C, R1).
///
/// Some photos produce a **confident podium of nonsense**. The 1948 Roosevelt list ranks "Gun",
/// "SALTY DOG!" and "Created at the Roosevelt"; the Thirsty Duck menu prints no beer prices at all,
/// so its only ranked items are OCR artifacts that happened to carry a number. Both are worse than
/// ranking nothing, because a ranked list is a claim: *this is the best value here*. El Perrito
/// already gets this right by accident — the photo is angled, so nothing parses.
///
/// **This flags, it does not withhold.** An earlier version suppressed the ranking entirely on a
/// thin read. That was the wrong call, and the 1948 list is why: once `PricePlausibility` withdraws
/// its four absurd prices, the top of its podium is `Individual Decanter Service` at $1.00 — a real
/// line for a decanter of whiskey, and genuinely the best value on the page. Withholding gave the
/// person nothing when a flagged, imperfect answer was available, which is the opposite of the
/// manual-edit-as-backstop design in R1. A ranking the person can see and correct beats silence.
///
/// The measure is one number, and it is the one that actually separates the corpus.
///
/// ### Mean OCR confidence does not work, and the intuition that it should is wrong
///
/// Measured across the eight dumps:
///
/// | Menu | mean Vision confidence | priced items |
/// |---|---|---|
/// | 1 | 0.946 | 45.2% |
/// | **2 (1948 list)** | **0.937** | **11.3%** |
/// | 3 (Rullo's) | **0.625** | 36.2% |
/// | 4 | 0.985 | 50.0% |
/// | 5 | 0.986 | 43.2% |
/// | 6 | 0.991 | 51.4% |
/// | 7 | 1.000 | 36.1% |
/// | **8 (Thirsty Duck)** | **1.000** | **5.3%** |
///
/// The two menus that must be condemned have mean confidences of 0.937 and **1.000** — Vision read
/// their glyphs perfectly and attached them to the wrong things. Meanwhile the *lowest* confidence
/// on the corpus, 0.625, belongs to Rullo's, which parses well and must not be condemned. **Any
/// confidence threshold that catches menus 2 and 8 destroys menu 3 first.** The earlier plan to use
/// mean confidence was a guess, and the data refutes it; don't re-derive it.
///
/// ### The priced fraction separates cleanly
///
/// Bad menus sit at 5.3% and 11.3%; good menus start at 36.1%. That is a **3.2× gap with nothing
/// inside it**, so the threshold is not finely tuned — anywhere in 12–36% gives identical verdicts
/// on all eight. The floor is set at 25%, nearer the good side, because wrongly condemning a real
/// menu costs the whole feature while wrongly passing one costs a list the person can see is junk.
///
/// It also has a real meaning rather than being a fitted statistic: the app's promise is that the
/// ranking describes *the menu*. If three quarters of the lines that parsed as drinks carry no
/// price, the ranking describes the quarter that did, and there is no reason to think that quarter
/// is representative.
///
/// ### `PricePlausibility` feeds this for free
///
/// A withdrawn price becomes a `needsPrice` item, which lowers the priced fraction by construction.
/// So a menu whose prices are being misread out of existence sinks toward the floor without the gate
/// needing to count withdrawals separately. That is why this is one signal and not three.
public struct MenuQuality: Equatable, Sendable {
    /// Parsed drink-ish lines considered.
    public let itemCount: Int
    /// How many of those carried a price.
    public let pricedCount: Int
    /// Too few priced lines for the ranking to describe the menu. The ranking is still produced;
    /// the UI should say the read was thin so the number is taken with the right amount of salt.
    public let isLowConfidence: Bool

    public init(itemCount: Int, pricedCount: Int, isLowConfidence: Bool) {
        self.itemCount = itemCount
        self.pricedCount = pricedCount
        self.isLowConfidence = isLowConfidence
    }

    public var pricedFraction: Double {
        itemCount > 0 ? Double(pricedCount) / Double(itemCount) : 0
    }

    /// A session built by hand (a manual entry flow, or a test) is trusted: the measure judges an
    /// OCR read, and there is nothing to judge here.
    public static let trusted = MenuQuality(itemCount: 0, pricedCount: 0, isLowConfidence: false)
}

public enum MenuQualityGate {
    /// Below this share of priced items the ranking is flagged as thin. See the type doc for why the
    /// exact value doesn't matter much: the measured gap runs 11.3% → 36.1%.
    public static let minimumPricedFraction = 0.25

    /// Fewer parsed items than this and there is no evidence to condemn on — the ratio is one or two
    /// lines wide, and a short list is one the person can check at a glance anyway. Silence beats a
    /// guess, in both directions.
    public static let minimumItemsToJudge = 8

    public static func assess(_ items: [MenuItem]) -> MenuQuality {
        let priced = items.reduce(into: 0) { count, item in
            if item.price != nil { count += 1 }
        }
        guard items.count >= minimumItemsToJudge else {
            return MenuQuality(itemCount: items.count, pricedCount: priced, isLowConfidence: false)
        }
        let fraction = Double(priced) / Double(items.count)
        return MenuQuality(itemCount: items.count, pricedCount: priced,
                           isLowConfidence: fraction < minimumPricedFraction)
    }
}
