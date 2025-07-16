import AudioKit
import AudioKitEX
import AVFoundation
import SoundpipeAudioKit

class MelodyPlayer: ObservableObject {
    private let engine = AudioEngine()
    private let sampler = AppleSampler()
    private var reverb: CostelloReverb
    private var mixer: DryWetMixer
    private var recorder: NodeRecorder?
    private var sequence: [Note] = []
    private var timer: Timer?
    private var currentIndex = 0
    private var isPlaying = false
    private var playbackSpeed: Double = 1.0 // 1.0 = normal speed
    @Published var isRecording: Bool = false
    var previewRecordingURL: URL? = nil // For SwiftUI Previews only
    
    init() {
        reverb = CostelloReverb(sampler)
        mixer = DryWetMixer(sampler, reverb, balance: 0.5)
        engine.output = mixer
        do {
            try engine.start()
            try sampler.loadSoundFont("SoundFont", preset: 0, bank: 5)
            // Recorder will be initialized before each recording
        } catch {
            print("AudioKit error: \(error)")
        }
    }
    
    func play(notes: [Note]) {
        stop()
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
    
    // MARK: - Recording
    func startRecording() {
        do {
            // Re-initialize recorder to ensure it's attached to a running node
            recorder = try NodeRecorder(node: mixer, fileDirectoryURL: FileManager.default.temporaryDirectory)
            try recorder?.reset()
            try recorder?.record()
            isRecording = true
            print("Recorder started: \(recorder?.isRecording ?? false)")
        } catch {
            print("Recording start error: \(error)")
        }
    }
    
    func stopRecording() {
        recorder?.stop()
        isRecording = false
        if let url = recorder?.audioFile?.url {
            print("Recorder stopped. File: \(url)")
            print("File exists: \(FileManager.default.fileExists(atPath: url.path))")
        } else {
            print("Recorder stopped. No file created.")
        }
    }
    
    func getRecordingURL() -> URL? {
        if let previewURL = previewRecordingURL { return previewURL }
        return recorder?.audioFile?.url
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
