//
//  TextBox.swift
//  Core
//
//  Created by Noval, Cameron on 8/27/26.
//


/// A recognized piece of text plus where it sat on the image — the pure, Foundation-free boundary
/// between Apple Vision (impure shell) and the pure `LineAssembler` (§7). The shell adapts each
/// `VNRecognizedTextObservation` into one of these; nothing in Core imports Vision.
///
/// Coordinates follow Vision's convention: normalized to `[0, 1]`, origin at the **bottom-left**,
/// y increasing **upward**. So a larger `midY` means higher on the page (read earlier).
public struct TextBox: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var height: Double { maxY - minY }
    public var width: Double { maxX - minX }
}

public struct TextObservation: Equatable, Sendable {
    public let text: String
    public let box: TextBox

    public init(text: String, box: TextBox) {
        self.text = text
        self.box = box
    }
}
