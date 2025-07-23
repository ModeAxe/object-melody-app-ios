import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Accelerate

struct VNMaskSegmentation: SegmentationStrategy {
    let name = "VNGenerateForegroundInstanceMask"
    
    func segmentObject(in image: UIImage, completion: @escaping (UIImage?) -> Void) {
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
                
                // Get masked Image
                let maskedImage = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
                let interceptCI = CIImage(cvPixelBuffer: maskedImage)
                let context = CIContext()
                let interceptCG = context.createCGImage(interceptCI, from: interceptCI.extent)!
                let intercept = UIImage(cgImage: interceptCG, scale: image.scale, orientation: image.imageOrientation)

                DispatchQueue.main.async {
                    completion(intercept)
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
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
