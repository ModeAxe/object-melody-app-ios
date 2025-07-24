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
    var currentSoundFont: SoundFont
    var currentSoundFontIndex = 0
    
    let soundFonts: [SoundFont] = [
        //SoundFont(name: "Default Sine", file: "SoundFont", preset: 0, bank: 5),
        SoundFont(name: "Piano", file: "TimGM6mb", preset: 2, bank: 0),
        SoundFont(name: "Celesta", file: "TimGM6mb", preset: 8, bank: 0),
        SoundFont(name: "Violin", file: "TimGM6mb", preset: 40, bank: 0),
        SoundFont(name: "Pan Flute", file: "TimGM6mb", preset: 75, bank: 0),
        SoundFont(name: "Contrabass", file: "TimGM6mb", preset: 43, bank: 0),
        SoundFont(name: "Tabular Bells", file: "TimGM6mb", preset: 14, bank: 0),
        SoundFont(name: "Glockenspiel", file: "TimGM6mb", preset: 9, bank: 0),
        SoundFont(name: "Halo Pad", file: "TimGM6mb", preset: 94, bank: 0),
        SoundFont(name: "Whistle", file: "TimGM6mb", preset: 78, bank: 0),
        SoundFont(name: "Birds", file: "TimGM6mb", preset: 123, bank: 0),
    ]

    init() {
        reverb = CostelloReverb(sampler)
        currentSoundFont = soundFonts[self.currentSoundFontIndex]
        mixer = DryWetMixer(sampler, reverb, balance: 0.5)
        engine.output = mixer
        do {
            try engine.start()
            try sampler.loadSoundFont(currentSoundFont.file, preset: currentSoundFont.preset, bank: currentSoundFont.bank)
        } catch {
            print("AudioKit error: \(error)")
        }
    }
    
    func play(notes: [Note]) {
        stop()
        if !engine.avEngine.isRunning {
            try? engine.start()
            try? sampler.loadSoundFont(currentSoundFont.file, preset: currentSoundFont.preset, bank: currentSoundFont.bank)
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
        engine.stop()
//        do {
//            try engine.stop()
//        } catch {
//            print("AudioKit engine stop error: \(error)")
//        }
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

    public func changeSoundFont(delta: Int) {
        currentSoundFontIndex = (currentSoundFontIndex + delta) % soundFonts.count
        currentSoundFont = soundFonts[currentSoundFontIndex]
        try? sampler.loadSoundFont(currentSoundFont.file, preset: currentSoundFont.preset, bank: currentSoundFont.bank)
    }
}

struct SoundFont {
    let name: String
    let file: String
    let preset: Int
    let bank: Int

    init(name: String, file: String, preset: Int, bank: Int) {
        self.name = name
        self.file = file
        self.preset = preset
        self.bank = bank
    }
}
