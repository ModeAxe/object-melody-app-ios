import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate

struct ImageSegmentation {
    static func segmentObject(in image: UIImage, completion: @escaping (UIImage?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                guard let result = request.results?.first as? VNInstanceMaskObservation else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                // Use the handler to generate the scaled mask
                let maskPixelBuffer = try result.generateScaledMaskForImage(forInstances: IndexSet(integer: 0), from: handler)
                // Use the original image's pixel size for resizing
                let targetSize = CGSize(width: cgImage.width, height: cgImage.height)
                let maskImage = maskFromPixelBuffer(pixelBuffer: maskPixelBuffer, targetSize: targetSize)
                let composite = applyMask(maskImage: maskImage, to: image)
                DispatchQueue.main.async {
                    completion(composite)
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}

// Helper: Create mask UIImage from pixelBuffer
private func maskFromPixelBuffer(pixelBuffer: CVPixelBuffer, targetSize: CGSize) -> UIImage {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    let context = CIContext()
    let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height))!
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    // Resize mask to match the original image's pixel dimensions
    let mask = UIImage(cgImage: cgImage).resize(to: targetSize)
    return mask
}

// Helper: Composite mask over original image (for now, just return the mask)
private func applyMask(maskImage: UIImage, to image: UIImage) -> UIImage? {
    // 1. Apply the mask using Core Image
    guard let ciImage = CIImage(image: image),
          let ciMask = CIImage(image: maskImage) else { return nil }
    let context = CIContext()
    // Invert the mask if needed (remove if not desired)
    let invertFilter = CIFilter.colorInvert()
    invertFilter.inputImage = ciMask
    guard let invertedMask = invertFilter.outputImage else { return nil }
    let transparent = CIImage(color: .clear).cropped(to: ciImage.extent)
    let blendFilter = CIFilter.blendWithMask()
    blendFilter.inputImage = ciImage
    blendFilter.backgroundImage = transparent
    blendFilter.maskImage = invertedMask
    guard let output = blendFilter.outputImage,
          let cgImage = context.createCGImage(output, from: ciImage.extent) else { return nil }
    var cutout = UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    
    cutout = UIImage(cgImage: cutout.cgImage.unsafelyUnwrapped, scale: cutout.scale, orientation: cutout.imageOrientation)
    
    // 3. Find the bounding box of non-transparent pixels
    guard let tightCGImage = cropToAlphaBounds_vImage(image: cutout) else { return nil }
    
    // 2. Crop 3 pixels from every edge
    let cropAmount = 25.0
    let cropRect = CGRect(x: cropAmount, y: cropAmount, width: cutout.size.width, height: cutout.size.height)
    let finalCropCGImage = tightCGImage.cropping(to: cropRect)
    
    return UIImage(cgImage: finalCropCGImage.unsafelyUnwrapped, scale: cutout.scale, orientation: cutout.imageOrientation)
}

// Helper: Crop to the bounding box of non-transparent pixels
private func cropToAlphaBounds(image: UIImage) -> CGImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        for x in 0..<width {
            let pixelIndex = y * bytesPerRow + x * bytesPerPixel
            let alpha = data.load(fromByteOffset: pixelIndex + 3, as: UInt8.self)
            if alpha > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    if minX > maxX || minY > maxY { return nil } // No non-transparent pixels
    let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    return cgImage.cropping(to: boundingBox)
}

private func cropToAlphaBounds_vImage(image: UIImage) -> CGImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = 4
    let bytesPerRow = bytesPerPixel * width
    let bitsPerComponent = 8
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    // Create vImage buffer for the image
    var srcBuffer = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    // Create buffer for alpha channel
    let alphaRowBytes = width
    guard let alphaData = malloc(height * alphaRowBytes) else { return nil }
    defer { free(alphaData) }
    var alphaBuffer = vImage_Buffer(data: alphaData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: alphaRowBytes)
    // Extract alpha channel
    let error = vImageExtractChannel_ARGB8888(&srcBuffer, &alphaBuffer, 3, vImage_Flags(kvImageNoFlags))
    guard error == kvImageNoError else { return nil }
    // Scan for non-zero alpha
    var minX = width, minY = height, maxX = 0, maxY = 0
    for y in 0..<height {
        let row = alphaData.advanced(by: y * alphaRowBytes)
        for x in 0..<width {
            let alpha = row.load(fromByteOffset: x, as: UInt8.self)
            if alpha > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
    }
    if minX > maxX || minY > maxY { return nil } // No non-transparent pixels
    let boundingBox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    return cgImage.cropping(to: boundingBox)
}

// Helper: Resize UIImage (unchanged)
extension UIImage {
    func resize(to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: size))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
} 
