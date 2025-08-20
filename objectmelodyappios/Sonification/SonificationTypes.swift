import Foundation

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
