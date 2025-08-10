import Foundation
import AVFoundation

struct ContentConfig {
    // Recording
    static let maxRecordingDuration: Double = 30.0

    // Cutout rendering
    static let cutoutRotationClamp: Double = 30.0

    // Audio modulation ranges
    static let minDelay: AUValue = 0.0
    static let maxDelay: AUValue = 1.0

    // UI delays
    static let swipeHintAppearDelay: TimeInterval = 1.5
}


