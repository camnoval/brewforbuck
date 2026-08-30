/// A serving volume, stored canonically in US fluid ounces. This is a pure unit type only — the
/// *typical* pours per category (pint, wine pour, shot) are domain assumptions that belong to
/// `BeverageKnowledge` (Phase 3), not here, so the model stays free of business defaults (§4, §7).
public struct Volume: Equatable, Hashable, Comparable, Sendable {
    public let fluidOunces: Double

    public init(fluidOunces: Double) { self.fluidOunces = fluidOunces }

    /// 1 US fluid ounce = 29.5735 mL.
    public init(milliliters: Double) { self.fluidOunces = milliliters / 29.5735 }
    public var milliliters: Double { fluidOunces * 29.5735 }

    /// Liters bridge for the store comparison's bottle sizes (750 mL, 1 L, 1.75 L).
    public init(liters: Double) { self.fluidOunces = (liters * 1000) / 29.5735 }
    public var liters: Double { milliliters / 1000 }

    public static let zero = Volume(fluidOunces: 0)

    public static func < (lhs: Volume, rhs: Volume) -> Bool { lhs.fluidOunces < rhs.fluidOunces }
}
