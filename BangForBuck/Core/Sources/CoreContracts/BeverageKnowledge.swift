import CoreModel

/// Where an estimated ABV/size came from — surfaced in the UI so the app is honest about whether a
/// value came from the sourced style chart or a category fallback (§11, R2). This is what lets the
/// app "say it fell back."
public enum EstimateSource: Equatable, Sendable {
    /// Matched a specific product in the brand table (highest confidence).
    case brandMatch(matched: String)
    /// Matched a known beer style / wine varietal in the chart (higher confidence).
    case styleChart(matched: String)
    /// No style match; used the section's category default (lower confidence).
    case categoryFallback
    /// No style match and no known section; used a generic estimate (lowest confidence).
    case unclassifiedFallback
}

/// A typical profile for a drink: its category and the typical ABV + pour to assume when the menu
/// didn't print them, plus where those came from.
public struct BeverageProfile: Equatable, Sendable {
    public let category: BeverageCategory
    /// Percent, e.g. 6.5.
    public let typicalABV: Double
    public let typicalSize: Volume
    public let source: EstimateSource

    public init(category: BeverageCategory, typicalABV: Double, typicalSize: Volume, source: EstimateSource) {
        self.category = category
        self.typicalABV = typicalABV
        self.typicalSize = typicalSize
        self.source = source
    }

    /// The human-readable assumption shown next to an estimate (§11).
    public var abvNote: String {
        switch source {
        case .brandMatch(let matched):
            return "matched \(matched) (brand, ~\(typicalABV)% ABV)"
        case .styleChart(let matched):
            return "matched \(matched) (style chart, ~\(typicalABV)% ABV)"
        case .categoryFallback:
            return "no style match, used typical \(category) (~\(typicalABV)% ABV)"
        case .unclassifiedFallback:
            return "unclassified, used a generic estimate (~\(typicalABV)% ABV)"
        }
    }
}

/// Maps a drink name (+ its menu section, if known) to a typical profile (§6). Real impl:
/// `StaticBeverageKnowledge` (pure, sourced). Kept behind a protocol so it's swappable/tunable
/// and testable.
public protocol BeverageKnowledge: Sendable {
    func profile(for name: String, sectionCategory: BeverageCategory?) -> BeverageProfile
}
