import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Musical Scale Definitions
struct Scale {
    let name: String
    let intervals: [Int] // Semitone intervals from tonic
    let description: String
}

struct MusicalParameters {
    let scale: Scale
    let tonic: String
    let basePitch: Int
}

// MARK: - Scale Definitions
extension Scale {
    static let fSharpDiatonic = Scale(
        name: "F# Diatonic",
        intervals: [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24], // F# major scale, 2 octaves
        description: "Bright, happy major scale"
    )
    
    static let major = Scale(
        name: "Major",
        intervals: [0, 2, 4, 5, 7, 9, 11, 12, 14, 16, 17, 19, 21, 23, 24],
        description: "Bright, happy major scale"
    )
    
    static let minor = Scale(
        name: "Minor",
        intervals: [0, 2, 3, 5, 7, 8, 10, 12, 14, 15, 17, 19, 20, 22, 24],
        description: "Melancholic, introspective minor scale"
    )
    
    static let pentatonic = Scale(
        name: "Pentatonic",
        intervals: [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24],
        description: "Simple, melodic 5-note scale"
    )
    
    static let blues = Scale(
        name: "Blues",
        intervals: [0, 3, 5, 6, 7, 10, 12, 15, 17, 18, 19, 22, 24],
        description: "Soulful, emotional blues scale"
    )
    
    static let dorian = Scale(
        name: "Dorian",
        intervals: [0, 2, 3, 5, 7, 9, 10, 12, 14, 15, 17, 19, 21, 22, 24],
        description: "Jazz/funk modal scale"
    )
    
    static let mixolydian = Scale(
        name: "Mixolydian",
        intervals: [0, 2, 4, 5, 7, 9, 10, 12, 14, 16, 17, 19, 21, 22, 24],
        description: "Rock/blues modal scale"
    )
    
    static let harmonicMinor = Scale(
        name: "Harmonic Minor",
        intervals: [0, 2, 3, 5, 7, 8, 11, 12, 14, 15, 17, 19, 20, 23, 24],
        description: "Dramatic, exotic harmonic minor"
    )
}

struct OutlineSonification: SonificationStrategy {
    let name = "Outline Method"
    
    func generateMelody(from image: UIImage) -> [Note] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        // Get musical parameters based on image color and brightness
        let musicalParams = getMusicalParameters(from: image)
        
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
        // 5. Map y-coordinates to MIDI pitches using the selected scale
        let minY = outlinePoints.map { $0.y }.min() ?? 0
        let maxY = outlinePoints.map { $0.y }.max() ?? 1
        let scale = musicalParams.scale.intervals
        let basePitch = musicalParams.basePitch
        var notes: [Note] = []
        for pt in outlinePoints {
            let norm = Double(pt.y - minY) / Double(max(1, maxY - minY))
            let scaleIdx = Int(norm * Double(scale.count - 1))
            let pitch = basePitch + scale[scaleIdx]
            notes.append(Note(pitch: pitch, velocity: 100, duration: 0.2))
        }
        return notes
    }
    
    // MARK: - Color and Brightness Analysis
    private func getMusicalParameters(from image: UIImage) -> MusicalParameters {
        let (hue, saturation, brightness) = getAverageColorValues(from: image)
        
        // Map hue to scale type
        let scale = getScaleFromHue(hue, saturation: saturation)
        
        // Map brightness to tonic
        let (tonic, basePitch) = getTonicFromBrightness(brightness)
        
        print("Scale: \(scale.name), Tonic: \(tonic), Base Pitch: \(basePitch)")
        
        return MusicalParameters(scale: scale, tonic: tonic, basePitch: basePitch)
    }
    
    private func getAverageColorValues(from image: UIImage) -> (hue: Double, saturation: Double, brightness: Double) {
        guard let cgImage = image.cgImage else { return (0, 0, 0.5) }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return (0, 0, 0.5) }
        
        var totalHue: Double = 0
        var totalSaturation: Double = 0
        var totalBrightness: Double = 0
        var pixelCount = 0
        
        // Sample pixels (every 10th pixel for performance)
        let step = 10
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let idx = (y * width + x) * bytesPerPixel
                let r = Double(ptr[idx]) / 255.0
                let g = Double(ptr[idx + 1]) / 255.0
                let b = Double(ptr[idx + 2]) / 255.0
                
                let (h, s, v) = rgbToHsv(r: r, g: g, b: b)
                totalHue += h
                totalSaturation += s
                totalBrightness += v
                pixelCount += 1
            }
        }
        
        return (
            hue: totalHue / Double(pixelCount),
            saturation: totalSaturation / Double(pixelCount),
            brightness: totalBrightness / Double(pixelCount)
        )
    }
    
    private func rgbToHsv(r: Double, g: Double, b: Double) -> (h: Double, s: Double, v: Double) {
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let delta = max - min
        
        var h: Double = 0
        let s = max == 0 ? 0 : delta / max
        let v = max
        
        if delta != 0 {
            if max == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if max == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        
        return (h, s, v)
    }
    
    // MARK: - Scale Selection Based on Hue
    private func getScaleFromHue(_ hue: Double, saturation: Double) -> Scale {

        if saturation < 0.1 { return  .minor}

        // 2-5) Hue split into four equal buckets across 360°
        switch hue {
        case 0..<90:
            return .dorian
        case 90..<180:
            return .pentatonic
        case 180..<270:
            return .fSharpDiatonic
        case 270..<360:
            return .major
        default:
            return .fSharpDiatonic
        }
    }
    
    // MARK: - Tonic Selection Based on Brightness
    private func getTonicFromBrightness(_ brightness: Double) -> (tonic: String, basePitch: Int) {
        // Map brightness to different keys across 2-3 octaves
        switch brightness {
        case 0..<0.2:     // Very Dark
            return ("C", 48)   // Low C
        case 0.2..<0.4:   // Dark
            return ("E", 52)   // Low E
        case 0.4..<0.6:   // Medium
            return ("G", 55)   // Low G
        case 0.6..<0.8:   // Bright
            return ("B", 59)   // Middle B
        case 0.8..<1.0:   // Very Bright
            return ("D", 62)   // High D
        default:
            return ("F#", 54)  // Default F# (middle range)
        }
    }
} 
