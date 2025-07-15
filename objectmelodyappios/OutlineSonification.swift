import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct OutlineSonification: SonificationStrategy {
    let name = "Outline Method"
    
    func generateMelody(from image: UIImage) -> [Note] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        // 1. Convert to grayscale
        let grayscale = ciImage.applyingFilter("CIPhotoEffectMono")
        // 2. Edge detection (Sobel)
        let edges = grayscale.applyingFilter("CIEdges", parameters: ["inputIntensity": 10.0])
        // 3. Threshold to get binary outline
        let thresholdFilter = CIFilter.colorClamp()
        thresholdFilter.inputImage = edges
        thresholdFilter.minComponents = CIVector(x: 0.8, y: 0.8, z: 0.8, w: 0)
        thresholdFilter.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let thresholded = thresholdFilter.outputImage,
              let outlineCG = context.createCGImage(thresholded, from: thresholded.extent) else { return [] }
        // 4. Sample points along the outline
        let width = outlineCG.width
        let height = outlineCG.height
        guard let data = outlineCG.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }
        var outlinePoints: [(x: Int, y: Int)] = []
        let bytesPerPixel = 4
        let step = max(1, width / 32) // sample up to 32 points
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                let idx = (y * width + x) * bytesPerPixel
                let r = ptr[idx]
                if r > 200 { // white pixel (edge)
                    outlinePoints.append((x, y))
                }
            }
        }
        if outlinePoints.isEmpty { return [] }
        // 5. Map y-coordinates to MIDI pitches (C pentatonic scale, 2 octaves)
        let minY = outlinePoints.map { $0.y }.min() ?? 0
        let maxY = outlinePoints.map { $0.y }.max() ?? 1
        let scale: [Int] = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24] // C pentatonic, 2 octaves
        let basePitch = 60 // Middle C
        var notes: [Note] = []
        for pt in outlinePoints {
            let norm = Double(pt.y - minY) / Double(max(1, maxY - minY))
            let scaleIdx = Int(norm * Double(scale.count - 1))
            let pitch = basePitch + scale[scaleIdx]
            notes.append(Note(pitch: pitch, velocity: 100, duration: 0.2))
        }
        return notes
    }
} 