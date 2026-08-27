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
        let observations = try await recognizeObservations(pngBytes: image.pngData)
        return LineAssembler.lines(from: observations)
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
                    let observations: [TextObservation] = results.compactMap { result in
                        guard let text = result.topCandidates(1).first?.string else { return nil }
                        let box = result.boundingBox   // normalized, origin bottom-left
                        return TextObservation(
                            text: text,
                            box: TextBox(
                                minX: Double(box.minX), minY: Double(box.minY),
                                maxX: Double(box.maxX), maxY: Double(box.maxY)
                            )
                        )
                    }
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
}
