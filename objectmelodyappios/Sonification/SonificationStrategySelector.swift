import UIKit

enum SonificationMethod: String, CaseIterable {
    case outline = "Outline"
    case grid = "Grid"
    case histogramChords = "Histogram Chords"
    
    var description: String {
        switch self {
        case .outline:
            return "Follows object edges for melodic lines"
        case .grid:
            return "Scans image grid for rhythmic patterns"
        case .histogramChords:
            return "Creates harmonic progressions from colors"
        }
    }
}

class SonificationStrategySelector: ObservableObject {
    @Published var currentMethod: SonificationMethod = .outline
    
    private var strategies: [SonificationMethod: SonificationStrategy] = [:]
    
    init() {
        // Initialize all strategies
        strategies[.outline] = OutlineSonification()
        strategies[.grid] = GridSonification()
        strategies[.histogramChords] = HistogramChordSonification()
        
        // Randomly select initial method for variety
        let randomMethod = SonificationMethod.allCases.randomElement() ?? .outline
        currentMethod = randomMethod
        print("🎵 Randomly selected initial sonification method: \(randomMethod.rawValue)")
    }
    
    var currentStrategy: SonificationStrategy {
        return strategies[currentMethod] ?? OutlineSonification()
    }
    
    func setMethod(_ method: SonificationMethod) {
        currentMethod = method
        print("🎵 Switched to \(method.rawValue) sonification")
    }
    
    func setMethodAndStopAudio(_ method: SonificationMethod, melodyPlayer: MelodyPlayer) {
        // Stop current audio playback
        melodyPlayer.kill()
        // Set new method
        setMethod(method)
    }
    
    func cycleToNextMethod() {
        let allMethods = SonificationMethod.allCases
        if let currentIndex = allMethods.firstIndex(of: currentMethod) {
            let nextIndex = (currentIndex + 1) % allMethods.count
            setMethod(allMethods[nextIndex])
        }
    }
    
    func cycleToPreviousMethod() {
        let allMethods = SonificationMethod.allCases
        if let currentIndex = allMethods.firstIndex(of: currentMethod) {
            let previousIndex = (currentIndex - 1 + allMethods.count) % allMethods.count
            setMethod(allMethods[previousIndex])
        }
    }
    
    func generateMelody(from image: UIImage) -> [Note] {
        return currentStrategy.generateMelody(from: image)
    }
}
