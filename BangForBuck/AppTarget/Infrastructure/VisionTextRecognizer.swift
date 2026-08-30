import Foundation
import Vision
import UIKit
import CoreContracts
import CoreModel
import CoreServices

/// The current Vision framework (the newer Swift Vision API) also declares a `TextObservation`,
/// which collides with our pure Core type inside this file (the only one importing `Vision`). Pin
/// both names to `CoreModel` so type lookup here is unambiguous; nothing else needs to change.
private typealias TextObservation = CoreModel.TextObservation
private typealias TextBox = CoreModel.TextBox

/// The real, on-device OCR (§6, Week 1): the impure shell that conforms `TextRecognizer` to Apple
/// **Vision** (`VNRecognizeTextRequest`) — on-device, free, no network, which is also the clean
/// privacy story for the App Store listing (no data collected, R3). It stays deliberately thin: it
/// only adapts Vision's results into the pure `TextObservation` values and hands them to the pure
/// `LineAssembler`. All the reading-order/row logic lives in Core where it's testable (§7).
///
/// Swap-in point (conventions §6/§14): inject this at app startup where a `TextRecognizer` is
/// needed; inject `FakeTextRecognizer` in tests. No `CoreServices`/`CoreModel` code changes to swap
/// the OCR engine.
struct VisionTextRecognizer: TextRecognizer {

    enum RecognizerError: Error { case invalidImageData }

    func recognizeLines(in image: CapturedImage) async throws -> [String] {
        LineAssembler.lines(from: try await recognizeObservations(in: image))
    }

    /// The raw observations before line assembly — the seam the debug OCR-export affordance taps to
    /// turn a mis-scanned photo into a `LineAssembler` fixture. Same Vision pass as `recognizeLines`.
    /// Spelled with the fully-qualified type because the file-private `TextObservation` typealias
    /// can't appear in an internal method's signature.
    func recognizeObservations(in image: CapturedImage) async throws -> [CoreModel.TextObservation] {
        try await recognizeObservations(pngBytes: image.pngData)
    }

    /// Decode + run Vision on a background queue so a large photo never blocks the main thread; the
    /// caller `await`s the result. `.accurate` + language correction suits printed menus.
    private func recognizeObservations(pngBytes: [UInt8]) async throws -> [TextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let cgImage = UIImage(data: Data(pngBytes))?.cgImage else {
                    continuation.resume(throwing: RecognizerError.invalidImageData)
                    return
                }

                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    let results = (request.results as? [VNRecognizedTextObservation]) ?? []

                    // Emit ONE observation per word, with that word's own bounding box, rather than
                    // one per Vision line. Vision groups text by baseline and will read straight
                    // across a two-column menu, returning a left-column item and a right-column item
                    // fused into a single line observation — which then reaches the parser as one
                    // chimera row ("COORS LIGHT … 5 BUDWEISER …"). Per-word boxes (via
                    // `boundingBox(for:)`) restore the true x-positions, so the empty gutter between
                    // columns reappears and `LineAssembler`'s X-Y cut can separate them. Words on the
                    // same row are rejoined there by vertical position, reproducing the original line.
                    var observations: [TextObservation] = []
                    for result in results {
                        guard let candidate = result.topCandidates(1).first else { continue }
                        let string = candidate.string
                        var wordCount = 0
                        for range in Self.wordRanges(in: string) {
                            let word = String(string[range])
                            if word.isEmpty { continue }
                            let boxObservation = try? candidate.boundingBox(for: range)
                            guard let rect = (boxObservation ?? nil)?.boundingBox else { continue }
                            observations.append(TextObservation(
                                text: word,
                                box: TextBox(minX: Double(rect.minX), minY: Double(rect.minY),
                                             maxX: Double(rect.maxX), maxY: Double(rect.maxY))
                            ))
                            wordCount += 1
                        }
                        // Fallback: if per-word geometry wasn't available, keep the whole-line box so
                        // no text is ever dropped (single-column menus are unaffected either way).
                        if wordCount == 0 {
                            let box = result.boundingBox
                            observations.append(TextObservation(
                                text: string,
                                box: TextBox(minX: Double(box.minX), minY: Double(box.minY),
                                             maxX: Double(box.maxX), maxY: Double(box.maxY))
                            ))
                        }
                    }
                    #if DEBUG
                    // Diagnostic: dump exactly what Vision produced (and what LineAssembler makes of
                    // it) to the Xcode console on every scan, so failures can be inspected without
                    // any in-app gesture. Copy this block from the console.
                    print("""

                    ===== BANGFORBUCK OCR EXPORT (start) =====
                    \(ObservationFixture.export(observations))
                    ===== BANGFORBUCK OCR EXPORT (end) =====

                    """)
                    #endif
                    continuation.resume(returning: observations)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US"]   // menus here are English; adjust to localize

                // PNG bytes bake orientation in, so `.up` is correct (see CapturedImage+UIImage).
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Split a recognized string into per-word index ranges (on spaces). The ranges index into the
    /// candidate's own string, which is what `boundingBox(for:)` requires.
    private static func wordRanges(in s: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var i = s.startIndex
        while i < s.endIndex {
            while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
            guard i < s.endIndex else { break }
            let start = i
            while i < s.endIndex, s[i] != " " { i = s.index(after: i) }
            ranges.append(start..<i)
        }
        return ranges
    }
}
