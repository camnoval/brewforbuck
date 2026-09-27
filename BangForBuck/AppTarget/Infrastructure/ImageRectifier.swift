//
//  ImageRectifier.swift
//  BangForBuck
//

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Perspective-correct a photo that did **not** come through `DocumentScanner`.
///
/// `VNDocumentCameraViewController` rectifies what it captures, so the scanner path needs nothing.
/// The photo-library path gets none of that: a picture of a curled menu taken at an angle arrives
/// exactly as shot, which is how row 1 of the tap list ended up drifting 0.0132 in y across its own
/// width. Without this, "scan a saved photo" and "scan with the camera" are not the same test, and
/// the capture fix can't be evaluated from the library at all.
///
/// `VNDetectDocumentSegmentationRequest` (iOS 15+, free, on-device) returns the document's quad in
/// normalized coordinates; `CIFilter.perspectiveCorrection` maps that quad back to a rectangle.
/// That is the same correction the document camera applies, minus the multi-frame capture and the
/// contrast enhancement.
///
/// Conservative by construction — every failure returns the original image untouched:
///
///  - no quad found (a menu photographed edge-to-edge with no visible border is common);
///  - **the quad is essentially the whole frame** (nothing to correct, and rectifying a
///    near-rectangle mostly resamples the image for no gain); or
///  - the filter or the render fails.
///
/// ⚠️ Three API names here rest on Apple's docs rather than on a compile:
/// `VNDetectDocumentSegmentationRequest`, its `results` being `[VNRectangleObservation]`, and
/// `CIFilter.perspectiveCorrection()`'s `topLeft`/`topRight`/`bottomLeft`/`bottomRight`/`crop`
/// properties. If any is wrong, deleting this file and the single `ImageRectifier.rectified` call
/// in `CaptureHomeView` restores today's behaviour exactly.
enum ImageRectifier {

    /// Below this, the detected quad is close enough to the full frame that correcting it is noise.
    private static let minimumCorrection = 0.02

    /// Works in PNG bytes rather than `UIImage` on purpose. Vision and Core Image are far too slow
    /// to run on the main actor — a full-resolution photo would freeze the screen — and `[UInt8]`
    /// is `Sendable` while `UIImage` and `CGImage` are not, so bytes are what can cross the hop
    /// cleanly. Same shape as `VisionTextRecognizer`'s existing off-main pattern.
    static func rectified(pngBytes: [UInt8]) async -> [UInt8] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: rectifiedSynchronously(pngBytes: pngBytes))
            }
        }
    }

    private static func rectifiedSynchronously(pngBytes: [UInt8]) -> [UInt8] {
        guard let image = UIImage(data: Data(pngBytes)), let cgImage = image.cgImage else {
            return pngBytes
        }

        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return pngBytes
        }
        guard let quad = (request.results as [VNRectangleObservation]?)?.first else { return pngBytes }

        // How far the quad's corners sit from the frame's corners, in normalized units. A photo
        // that is already square-on scores ~0 and is left alone.
        let displacement = max(
            distance(quad.topLeft, CGPoint(x: 0, y: 1)),
            distance(quad.topRight, CGPoint(x: 1, y: 1)),
            distance(quad.bottomLeft, CGPoint(x: 0, y: 0)),
            distance(quad.bottomRight, CGPoint(x: 1, y: 0))
        )
        guard displacement >= minimumCorrection else { return pngBytes }

        let source = CIImage(cgImage: cgImage)
        let width = source.extent.width
        let height = source.extent.height
        func point(_ normalized: CGPoint) -> CGPoint {
            // Vision's normalized quad and CIImage both use a bottom-left origin, so no flip.
            CGPoint(x: normalized.x * width, y: normalized.y * height)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomLeft = point(quad.bottomLeft)
        filter.bottomRight = point(quad.bottomRight)
        filter.crop = true

        guard let output = filter.outputImage,
              let rendered = CIContext().createCGImage(output, from: output.extent),
              let encoded = UIImage(cgImage: rendered).pngData()
        else { return pngBytes }

        #if DEBUG
        print("""
        ===== BANGFORBUCK RECTIFY =====
        # \(cgImage.width)x\(cgImage.height) -> \(rendered.width)x\(rendered.height) px
        # corner displacement \(String(format: "%.3f", displacement)) (threshold \(minimumCorrection))
        """)
        #endif
        return [UInt8](encoded)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }
}
