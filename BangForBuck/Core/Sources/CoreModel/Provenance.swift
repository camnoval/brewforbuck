/// Every estimable axis carries where its value came from, so a guess can never silently pass as
/// a fact (§11, R2). `read` = taken straight off the menu; `estimated` = inferred, with a
/// human-readable note explaining the assumption (e.g. "assumed 16 oz pint").
///
/// The whole app hangs off this: the Results UI renders estimated axes distinctly and lets the
/// user correct any estimate inline, which promotes it to `.read` and re-ranks.
public enum Provenance<Value> {
    case read(Value)
    case estimated(Value, note: String)

    /// The underlying value regardless of provenance — this is what you *compute* with. The
    /// provenance itself (not the value) is what the UI must surface.
    public var value: Value {
        switch self {
        case .read(let v): return v
        case .estimated(let v, _): return v
        }
    }

    public var isEstimated: Bool {
        if case .estimated = self { return true }
        return false
    }

    /// The assumption behind an estimate ("assumed 16 oz pint"), or `nil` when read.
    public var note: String? {
        if case .estimated(_, let note) = self { return note }
        return nil
    }

    /// Correcting an estimate inline promotes it to `.read` (§11) — the user has supplied a real
    /// value, so it is no longer a guess.
    public func corrected(to newValue: Value) -> Provenance {
        .read(newValue)
    }

    /// Transform the wrapped value while preserving provenance (and the note).
    public func map<T>(_ transform: (Value) -> T) -> Provenance<T> {
        switch self {
        case .read(let v): return .read(transform(v))
        case .estimated(let v, let note): return .estimated(transform(v), note: note)
        }
    }
}

extension Provenance: Equatable where Value: Equatable {}
extension Provenance: Hashable where Value: Hashable {}
extension Provenance: Sendable where Value: Sendable {}
