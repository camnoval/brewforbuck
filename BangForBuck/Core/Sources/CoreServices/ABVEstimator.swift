import CoreModel
import CoreContracts

/// Resolve a drink's ABV with provenance (§7, §11): the menu's printed value is `.read`; otherwise
/// the profile's typical value is `.estimated`, carrying the profile's note (brand / style / fallback).
public enum ABVEstimator {
    public static func estimate(_ item: MenuItem, profile: BeverageProfile) -> Provenance<Double> {
        if let printed = item.readABV { return .read(printed) }
        return .estimated(profile.typicalABV, note: profile.abvNote)
    }
}
