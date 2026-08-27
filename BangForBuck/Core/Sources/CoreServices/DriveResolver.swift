//
//  DriveResolver.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//

import CoreModel
import CoreContracts

/// The single, pure enrichment step (§7): one parsed `MenuItem` → either an alcoholic
/// `EditableDrink` (with ABV/size resolved via `BeverageKnowledge`, `.read` if printed else
/// `.estimated`) or a non-alcoholic exclusion. Both `MenuPipeline.analyze` (the one-shot snapshot)
/// and `MenuPipeline.makeSession` (the editable flow) route through here, so estimates, notes, and
/// the Change-B exclusion are computed *identically* on both paths and can't drift.
public enum DrinkResolver {

    /// Resolve one item. Exactly one of the returned fields is non-nil:
    /// - `drink` for an alcoholic item (may still be `needsPrice`).
    /// - `excludedName` for a non-alcoholic item (Change B) — never ranked.
    public static func resolve(
        _ item: MenuItem,
        id: Int,
        knowledge: BeverageKnowledge
    ) -> (drink: EditableDrink?, excludedName: String?) {
        // A `.unknown` section gives the knowledge layer no hint; pass nil so it can fall back.
        let sectionCategory: BeverageCategory? = item.category == .unknown ? nil : item.category
        let profile = knowledge.profile(for: item.name, sectionCategory: sectionCategory)

        // Non-alcoholic by section or brand → excluded before the metric ever runs (Change B).
        if profile.category == .nonAlcoholic {
            return (nil, item.name)
        }

        let drink = EditableDrink(
            id: id,
            name: item.name,
            category: profile.category,
            price: item.price,                                   // may be nil ⇒ needsPrice (§10)
            abv: ABVEstimator.estimate(item, profile: profile),  // .read if printed, else .estimated
            size: SizeEstimator.estimate(item, profile: profile)
        )
        return (drink, nil)
    }
}
