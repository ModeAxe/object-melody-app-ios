import UIKit
import CoreImage

struct GridSonification: SonificationStrategy {
    let name = "Grid Method"
    
    func generateMelody(from image: UIImage) -> [Note] {
        guard let cgImage = image.cgImage else { return [] }
        
        // Get musical parameters based on image color and brightness
        let musicalParams = getMusicalParameters(from: image)
        
        // Convert to grayscale for brightness analysis
        let ciImage = CIImage(cgImage: cgImage)
        let grayscale = ciImage.applyingFilter("CIPhotoEffectMono")
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create a grid: 8 columns (time steps) x 6 rows (pitch range)
        let gridCols = 8
        let gridRows = 6
        let cellWidth = width / gridCols
        let cellHeight = height / gridRows
        
        var notes: [Note] = []
        let scale = musicalParams.scale.intervals
        let basePitch = musicalParams.basePitch
        
        // Scan through each column (time step)
        for col in 0..<gridCols {
            let colNotes: [Note] = []
            
            // For each row in this column, check if we should play a note
            for row in 0..<gridRows {
                let x = col * cellWidth + cellWidth / 2
                let y = row * cellHeight + cellHeight / 2
                
                // Get brightness at this grid point
                let brightness = getBrightnessAt(image: cgImage, x: x, y: y)
                
                // Only play note if brightness is above threshold (darker areas = more notes)
                if brightness < 0.7 {
                    let pitch = basePitch + scale[row % scale.count]
                    let velocity = Int((1.0 - brightness) * 127) // Darker = louder
                    let duration = 0.15 // Short, rhythmic notes
                    
                    notes.append(Note(pitch: pitch, velocity: velocity, duration: duration))
                }
            }
        }
        
        return notes
    }
    
    private func getBrightnessAt(image: CGImage, x: Int, y: Int) -> Double {
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return 0.5 }
        
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        let idx = (y * bytesPerRow) + (x * bytesPerPixel)
        
        let r = Double(ptr[idx]) / 255.0
        let g = Double(ptr[idx + 1]) / 255.0
        let b = Double(ptr[idx + 2]) / 255.0
        
        // Convert to brightness (luminance)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }
    
    // MARK: - Color and Brightness Analysis (reused from OutlineSonification)
    private func getMusicalParameters(from image: UIImage) -> MusicalParameters {
        let (hue, saturation, brightness) = getAverageColorValues(from: image)
        
        // Map hue to scale type
        let scale = getScaleFromHue(hue, saturation: saturation)
        
        // Map brightness to tonic
        let (tonic, basePitch) = getTonicFromBrightness(brightness)
        
        print("Grid Sonification - Scale: \(scale.name), Tonic: \(tonic), Base Pitch: \(basePitch)")
        
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
    
    private func getScaleFromHue(_ hue: Double, saturation: Double) -> Scale {
        if saturation < 0.1 { return .fSharpDiatonic }
        
        switch hue {
        case 0..<90:      return .dorian
        case 90..<180:    return .pentatonic
        case 180..<270:   return .fSharpDiatonic
        case 270..<360:   return .major
        default:          return .fSharpDiatonic
        }
    }
    
    private func getTonicFromBrightness(_ brightness: Double) -> (tonic: String, basePitch: Int) {
        switch brightness {
        case 0..<0.2:     return ("C", 48)
        case 0.2..<0.4:   return ("E", 52)
        case 0.4..<0.6:   return ("G", 55)
        case 0.6..<0.8:   return ("B", 59)
        case 0.8..<1.0:   return ("D", 62)
        default:           return ("F#", 54)
        }
    }
}
