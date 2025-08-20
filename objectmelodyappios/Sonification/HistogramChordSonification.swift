import UIKit
import CoreImage

struct HistogramChordSonification: SonificationStrategy {
    let name = "Histogram Chords"
    
    func generateMelody(from image: UIImage) -> [Note] {
        guard let cgImage = image.cgImage else { return [] }
        
        // Get musical parameters based on image color and brightness
        let musicalParams = getMusicalParameters(from: image)
        
        // Analyze color histogram
        let histogram = getColorHistogram(from: cgImage)
        
        // Create chord progression based on dominant colors
        let chords = createChordProgression(from: histogram, scale: musicalParams.scale, basePitch: musicalParams.basePitch)
        
        // Convert chords to notes (arpeggiate)
        var notes: [Note] = []
        let noteDuration = 0.2
        
        for (index, chord) in chords.enumerated() {
            // Add all notes from this chord
            for (noteIndex, pitch) in chord.enumerated() {
                notes.append(Note(
                    pitch: pitch,
                    velocity: 80 + (noteIndex * 10), // Slight velocity variation
                    duration: noteDuration
                ))
            }
        }
        
        return notes
    }
    
    private func getColorHistogram(from image: CGImage) -> [Double] {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let data = image.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return Array(repeating: 0.5, count: 12) }
        
        // Create 12 color buckets (like a chromatic scale)
        var histogram = Array(repeating: 0.0, count: 12)
        var totalPixels = 0
        
        // Sample pixels for performance
        let step = 5
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let idx = (y * width + x) * bytesPerPixel
                let r = Double(ptr[idx]) / 255.0
                let g = Double(ptr[idx + 1]) / 255.0
                let b = Double(ptr[idx + 2]) / 255.0
                
                // Convert RGB to hue and map to 12 buckets
                let hue = rgbToHue(r: r, g: g, b: b)
                let bucket = Int((hue / 360.0) * 12.0) % 12
                
                histogram[bucket] += 1.0
                totalPixels += 1
            }
        }
        
        // Normalize histogram
        if totalPixels > 0 {
            for i in 0..<histogram.count {
                histogram[i] = histogram[i] / Double(totalPixels)
            }
        }
        
        return histogram
    }
    
    private func createChordProgression(from histogram: [Double], scale: Scale, basePitch: Int) -> [[Int]] {
        // Find the 3-4 most dominant color buckets
        let sortedBuckets = histogram.enumerated().sorted { $0.element > $1.element }
        let dominantBuckets = Array(sortedBuckets.prefix(4))
        
        var chords: [[Int]] = []
        let scaleIntervals = scale.intervals
        
        for bucket in dominantBuckets {
            let bucketIndex = bucket.offset
            let intensity = bucket.element
            
            // Skip very weak colors
            if intensity < 0.05 { continue }
            
            // Create a chord based on this color bucket
            let chord = createChordFromBucket(
                bucketIndex: bucketIndex,
                scale: scaleIntervals,
                basePitch: basePitch,
                intensity: intensity
            )
            
            if !chord.isEmpty {
                chords.append(chord)
            }
        }
        
        // If no chords were created, create a simple triad
        if chords.isEmpty {
            let root = basePitch + scaleIntervals[0]
            let third = basePitch + scaleIntervals[2]
            let fifth = basePitch + scaleIntervals[4]
            chords.append([root, third, fifth])
        }
        
        return chords
    }
    
    private func createChordFromBucket(bucketIndex: Int, scale: [Int], basePitch: Int, intensity: Double) -> [Int] {
        // Map bucket index to scale degrees
        let scaleIndex = bucketIndex % scale.count
        let root = basePitch + scale[scaleIndex]
        
        // Create different chord types based on intensity
        var chord: [Int] = [root]
        
        if intensity > 0.15 {
            // Major chord (root, major third, perfect fifth)
            if scaleIndex + 2 < scale.count {
                chord.append(basePitch + scale[scaleIndex + 2])
            }
            if scaleIndex + 4 < scale.count {
                chord.append(basePitch + scale[scaleIndex + 4])
            }
        } else if intensity > 0.08 {
            // Power chord (root, perfect fifth)
            if scaleIndex + 4 < scale.count {
                chord.append(basePitch + scale[scaleIndex + 4])
            }
        }
        
        return chord
    }
    
    private func rgbToHue(r: Double, g: Double, b: Double) -> Double {
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let delta = max - min
        
        var h: Double = 0
        
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
        
        return h
    }
    
    // MARK: - Color and Brightness Analysis (reused from OutlineSonification)
    private func getMusicalParameters(from image: UIImage) -> MusicalParameters {
        let (hue, saturation, brightness) = getAverageColorValues(from: image)
        
        // Map hue to scale type
        let scale = getScaleFromHue(hue, saturation: saturation)
        
        // Map brightness to tonic
        let (tonic, basePitch) = getTonicFromBrightness(brightness)
        
        print("Histogram Chords - Scale: \(scale.name), Tonic: \(tonic), Base Pitch: \(basePitch)")
        
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
