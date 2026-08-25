import CoreModel

/// A Foundation-free handle for a captured photo. The impure shell (`VisionTextRecognizer`,
/// Week 1) fills this with encoded image bytes; keeping it byte-based means `CoreContracts`
/// imports no Apple frameworks and stays a pure Core module (§4, §7).
public struct CapturedImage: Equatable, Sendable {
    public let pngData: [UInt8]
    public init(pngData: [UInt8]) { self.pngData = pngData }
}

/// Turns a photo into OCR text lines (§6). Real impl: Apple Vision on-device (Week 1). Test impl:
/// `FakeTextRecognizer`, which returns canned fixture lines. The pure pipeline downstream consumes
/// only `[String]`, so the whole value engine is testable without a camera.
public protocol TextRecognizer: Sendable {
    func recognizeLines(in image: CapturedImage) async throws -> [String]
}
