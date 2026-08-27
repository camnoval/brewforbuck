//
//  CapturedImage+UIImage.swift
//  BangForBuck
//
//  Created by Noval, Cameron on 8/27/26.
//

import UIKit
import CoreContracts

/// Bridges a UIKit `UIImage` (from the camera or photo library) into the Foundation-free
/// `CapturedImage` the `TextRecognizer` contract accepts. Encoding through PNG bakes any EXIF
/// orientation into the pixels, so the recognizer can safely treat the image as upright (`.up`) and
/// we avoid rotated-text OCR misreads.
extension CapturedImage {
    init?(uiImage: UIImage) {
        guard let data = uiImage.pngData() else { return nil }
        self.init(pngData: [UInt8](data))
    }
}
