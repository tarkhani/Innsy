//
//  InferenceJPEG.swift
//  Innsy
//

import UIKit

/// Downscales photos before multimodal inference so small GPUs do not OOM.
enum InferenceJPEG {
    private static let maxPixelSide: CGFloat = 768
    private static let quality: CGFloat = 0.82

    static func dataForModel(from image: UIImage) -> Data? {
        let pxW = image.size.width * image.scale
        let pxH = image.size.height * image.scale
        let longSide = max(pxW, pxH)
        guard longSide > 1 else { return nil }

        let outImage: UIImage
        if longSide <= maxPixelSide {
            outImage = image
        } else {
            let s = maxPixelSide / longSide
            let outW = max(1, pxW * s)
            let outH = max(1, pxH * s)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: outW, height: outH), format: format)
            outImage = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: outW, height: outH))
            }
        }
        return outImage.jpegData(compressionQuality: quality)
    }
}
