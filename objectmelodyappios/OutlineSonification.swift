import UIKit

struct OutlineSonification: SonificationStrategy {
    let name = "Outline Method"
    
    func generateMelody(from image: UIImage) -> [Note] {
        // TODO: Implement outline extraction and mapping to notes
        // For now, return a simple C major scale as a placeholder
        return [
            Note(pitch: 60, velocity: 100, duration: 0.3),
            Note(pitch: 62, velocity: 100, duration: 0.3),
            Note(pitch: 64, velocity: 100, duration: 0.3),
            Note(pitch: 65, velocity: 100, duration: 0.3),
            Note(pitch: 67, velocity: 100, duration: 0.3),
            Note(pitch: 69, velocity: 100, duration: 0.3),
            Note(pitch: 71, velocity: 100, duration: 0.3),
            Note(pitch: 72, velocity: 100, duration: 0.3)
        ]
    }
} 