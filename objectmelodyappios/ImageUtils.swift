import UIKit

/// Crops a UIImage by a number of pixels from each edge.
/// - Parameters:
///   - image: The UIImage to crop.
///   - pixels: The number of pixels to crop from each edge.
/// - Returns: The cropped UIImage, or nil if cropping fails.
func cropImage(_ image: UIImage, by pixels: CGFloat) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let cropRect = CGRect(x: pixels, y: pixels, width: width - 2 * pixels, height: height - 2 * pixels)
    guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
    return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
}
