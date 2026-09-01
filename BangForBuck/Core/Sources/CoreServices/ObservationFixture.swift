//
//  ObservationFixture.swift
//  Core
//
//  Created by Noval, Cameron on 8/30/26.
//


import CoreModel

/// Turns captured OCR observations into a checked-in regression test. This is the bridge from "a
/// photo that scanned wrong on device" to "a permanent fixture": the app's debug export affordance
/// runs Vision on a photo, hands the raw `[TextObservation]` here, and shares the result. It emits
/// two things — a **paste-ready Swift literal** you drop straight into a `LineAssembler` test, and a
/// **readable dump** (each box's position plus the lines `LineAssembler` currently produces) so you
/// can see at a glance where a layout goes wrong. Pure and Foundation-free, so it's testable here
/// without a camera and the coordinate formatting is deterministic.
public enum ObservationFixture {

    /// `let observations: [TextObservation] = [ TextObservation(...), ... ]` — paste into a test.
    public static func swiftLiteral(_ observations: [TextObservation], name: String = "observations") -> String {
        var out = "let \(name): [TextObservation] = [\n"
        for o in observations {
            let b = o.box
            out += "    TextObservation(text: \(quoted(o.text)), "
            out += "box: TextBox(minX: \(fmt(b.minX)), minY: \(fmt(b.minY)), maxX: \(fmt(b.maxX)), maxY: \(fmt(b.maxY)))),\n"
        }
        out += "]\n"
        return out
    }

    /// Readable dump: each observation top-to-bottom as `"text" @ midX,midY  w×h`, then the lines
    /// `LineAssembler` builds right now — so a wrong split is obvious without pasting anything.
    public static func debugDump(_ observations: [TextObservation]) -> String {
        var out = "# \(observations.count) observations  (\"text\" @ midX,midY  w×h)\n"
        let topToBottom = observations.sorted { $0.box.midY > $1.box.midY }  // Vision y up → descending
        for o in topToBottom {
            let b = o.box
            out += "\(quoted(o.text)) @ \(fmt(b.midX)),\(fmt(b.midY))  \(fmt(b.width))×\(fmt(b.height))\n"
        }
        let lines = LineAssembler.lines(from: observations)
        out += "\n# LineAssembler.lines output (\(lines.count)):\n"
        for line in lines { out += "  \(line)\n" }
        return out
    }

    /// The full artifact to share: literal followed by the readable dump.
    public static func export(_ observations: [TextObservation], name: String = "observations") -> String {
        swiftLiteral(observations, name: name) + "\n" + debugDump(observations)
    }

    // MARK: - Foundation-free helpers

    /// Round to 4 decimals and trim trailing zeros: `0.05`, `0.8`, `0.3266`, `1`.
    static func fmt(_ x: Double) -> String {
        let rounded = (x * 10000).rounded()          // half-away-from-zero
        let negative = rounded < 0
        let scaled = Int(abs(rounded))
        let whole = scaled / 10000
        let frac = scaled % 10000
        let body: String
        if frac == 0 {
            body = "\(whole)"
        } else {
            var digits = Array(pad4(frac))
            while digits.last == "0" { digits.removeLast() }
            body = "\(whole).\(String(digits))"
        }
        return negative ? "-" + body : body
    }

    static func pad4(_ n: Int) -> String {
        var s = "\(n)"
        while s.count < 4 { s = "0" + s }
        return s
    }

    static func quoted(_ s: String) -> String {
        var out = "\""
        for c in s {
            switch c {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(c)
            }
        }
        out += "\""
        return out
    }
}
