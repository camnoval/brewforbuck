//
//  DocumentScanner.swift
//  BangForBuck
//

import SwiftUI
import VisionKit

/// The system document scanner — the one from Notes — in place of a plain camera shot.
///
/// **Why this replaces `CameraPicker`.** Two of the reading failures found on 09-27 were not
/// reading failures at all; they were capture failures that the reader was being asked to
/// compensate for:
///
///  - a row of the tap list drifted 0.0132 in y across its own width, because the paper was curled
///    in someone's hand, which tore `1 - IC LIGHT` away from `4.2% ABV`; and
///  - the bar was dim and the card was laminated, so glyphs came back as `$` → `5`.
///
/// `VNDocumentCameraViewController` does what a camera doesn't: real-time edge detection with a
/// live quad on the viewfinder, automatic capture, cropping, **perspective correction**, and
/// document enhancement (deskew, flatten, contrast). A photo records what the camera saw — the
/// angle, the lighting, the curl. A scan records a normalized page. Fixing it here is strictly
/// better than teaching `LineAssembler` to tolerate it, and the live quad also tells someone
/// standing at a bar that they're too far away or too skewed, which nothing currently does.
///
/// **Multi-page is free, so it's on.** Menus are two-sided constantly. Each kept page is OCR'd and
/// the lines are concatenated in page order, so front and back rank together. Nothing is captured
/// without the person tapping Keep Scan, so accidental duplicate pages aren't a real risk.
///
/// Requires `NSCameraUsageDescription` (already present for `CameraPicker`). iOS 13+, so no
/// availability gate is needed; `isSupported` is checked anyway because it is `false` on devices
/// without the necessary camera support, and `CameraPicker` remains as the fallback.
struct DocumentScanner: UIViewControllerRepresentable {
    /// Called with every page the person kept, in order. Empty if they cancelled.
    let onPages: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var pages: [UIImage] = []
            for index in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: index))
            }
            parent.onPages(pages)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onPages([])
            parent.dismiss()
        }

        /// A scan can fail mid-session (camera interrupted, memory). Treat it as a cancel rather
        /// than leaving the sheet up: the person can retake, and `CaptureHomeView` still has the
        /// photo-library path.
        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onPages([])
            parent.dismiss()
        }
    }
}
