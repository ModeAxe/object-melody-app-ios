import UIKit

// MARK: - Note Model
struct Note {
    let pitch: Int      // MIDI note number
    let velocity: Int   // 0-127
    let duration: Double // seconds
}

// MARK: - Sonification Strategy Protocol
protocol SonificationStrategy {
    func generateMelody(from image: UIImage) -> [Note]
    var name: String { get }
}

// MARK: - Sonification Manager
class SonificationManager {
    private var strategy: SonificationStrategy
    
    init(strategy: SonificationStrategy) {
        self.strategy = strategy
    }
    
    func setStrategy(_ strategy: SonificationStrategy) {
        self.strategy = strategy
    }
    
    func generateMelody(from image: UIImage) -> [Note] {
        return strategy.generateMelody(from: image)
    }
    
    var currentStrategyName: String {
        return strategy.name
    }
} 