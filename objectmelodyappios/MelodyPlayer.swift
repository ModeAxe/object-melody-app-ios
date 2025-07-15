import Foundation
import AudioKit
import AudioKitEX
import AVFoundation
import SoundpipeAudioKit

class MelodyPlayer: ObservableObject {
    private let engine = AudioEngine()
    private let sampler = AppleSampler()
    private var reverb: CostelloReverb
    private var mixer: DryWetMixer
    private var sequence: [Note] = []
    private var timer: Timer?
    private var currentIndex = 0
    private var isPlaying = false
    private var playbackSpeed: Double = 1.0 // 1.0 = normal speed
    
    init() {
        reverb = CostelloReverb(sampler)
        mixer = DryWetMixer(sampler, reverb, balance: 0.5)
        engine.output = mixer
        do {
            try engine.start()
            try sampler.loadSoundFont("SoundFont", preset: 0, bank: 5)
        } catch {
            print("AudioKit error: \(error)")
        }
    }
    
    func play(notes: [Note]) {
        stop()
        // Make sure the engine is running
        if !engine.avEngine.isRunning {
            try? engine.start()
        }
        sequence = notes
        print("Playing melody with \(notes.count) notes")
        currentIndex = 0
        isPlaying = true
        scheduleNextNote()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
    
    func kill() {
        stop()
        do {
            try engine.stop()
        } catch {
            print("AudioKit engine stop error: \(error)")
        }
        for note in sequence {
            sampler.stop(noteNumber: MIDINoteNumber(note.pitch), channel: 0)
        }
    }
    
    func setReverbMix(_ value: AUValue) {
        mixer.balance = value // 0.0 = dry, 1.0 = wet
    }
    
    func setPlaybackSpeed(_ value: Double) {
        playbackSpeed = value // 0.5 = half speed, 2.0 = double speed
    }
    
    private func scheduleNextNote() {
        guard isPlaying, !sequence.isEmpty else { return }
        let note = sequence[currentIndex]
        sampler.play(noteNumber: MIDINoteNumber(note.pitch), velocity: MIDIVelocity(note.velocity), channel: 0)
        let interval = note.duration / playbackSpeed
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.sampler.stop(noteNumber: MIDINoteNumber(note.pitch), channel: 0)
            self.currentIndex += 1
            if self.currentIndex >= self.sequence.count {
                self.currentIndex = 0 // Loop
            }
            self.scheduleNextNote()
        }
    }
} 
