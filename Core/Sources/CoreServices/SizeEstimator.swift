import CoreModel
import CoreContracts

/// Resolve a drink's serving size with provenance (§7, §11): printed size is `.read`; otherwise the
/// profile's typical pour is `.estimated`, with a note explaining the assumption.
public enum SizeEstimator {
    public static func estimate(_ item: MenuItem, profile: BeverageProfile) -> Provenance<Volume> {
        if let printed = item.readSize { return .read(printed) }
        let note = "assumed \(profile.typicalSize.fluidOunces) oz for \(profile.category)"
        return .estimated(profile.typicalSize, note: note)
    }
}
