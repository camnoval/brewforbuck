//
//  CameraPicker.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/27/26.
//


import SwiftUI
import UIKit

/// A minimal SwiftUI wrapper over `UIImagePickerController` for a single still photo from the
/// camera. Deliberately simple (no live AVFoundation preview) — that's the robust, cut-line-safe
/// choice for v1; live preview is on the "cut first if time slips" list. Requires the
/// `NSCameraUsageDescription` Info.plist key (see the placement notes).
struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the captured photo; the picker dismisses itself either way.
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}