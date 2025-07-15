import UIKit

struct SimpleFeatureSonification: SonificationStrategy {
    let name = "Simple Feature Method"
    
    func generateMelody(from image: UIImage) -> [Note] {
        // TODO: Implement feature extraction and mapping to notes
        // For now, return a simple repeating note as a placeholder
        return [
            Note(pitch: 60, velocity: 100, duration: 0.5),
            Note(pitch: 64, velocity: 100, duration: 0.5),
            Note(pitch: 67, velocity: 100, duration: 0.5),
            Note(pitch: 72, velocity: 100, duration: 0.5)
        ]
    }
} 