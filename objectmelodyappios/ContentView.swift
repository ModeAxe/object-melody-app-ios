//
//  ContentView.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/14/25.
//

import SwiftUI
import AVFoundation
import Vision

// Sonification & Playback
import AudioKit
import AudioKitEX
import CoreMotion

// App states / phases
enum AppFlowState {
    case camera
    case processing
    case playback
    case recording
}

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var pitch: Double = 0.0
    @Published var roll: Double = 0.0
    @Published var yaw: Double = 0.0
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.pitch = motion.attitude.pitch
            self.roll = motion.attitude.roll
            self.yaw = motion.attitude.yaw
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct ContentView: View {
    @State private var appState: AppFlowState = .camera // Start with camera open
    @State private var capturedImage: UIImage? = nil
    @State private var segmentedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    @State private var isPlaying: Bool = false
    @State private var isRecording: Bool = false
    @State private var hasRecording: Bool = false
    @State private var isPreviewing: Bool = false
    @State private var showDeleteConfirm: Bool = false
    // Melody player and sonification
    @StateObject private var melodyPlayer = MelodyPlayer()
    private let sonification = OutlineSonification()
    @State private var currentMelody: [Note] = []
    @StateObject private var motionManager = MotionManager()
    @State private var audioPlayer: AVAudioPlayer?
    @State private var showShareSheet: Bool = false
    @State private var shareURL: URL?
    @State private var showDocumentPicker: Bool = false
    @State private var documentPickerURL: URL? = nil
    
    // 1. Add state for preview progress
    @State private var previewProgress: Double = 0.0
    @State private var previewTimer: Timer? = nil
    
    // Add recording progress state
    @State private var recordingProgress: Double = 0.0
    @State private var recordingTimer: Timer? = nil
    let maxRecordingDuration: Double = 30.0 // 30 seconds
    
    // Clamp value for cutout rotation (in degrees)
    let cutoutRotationClamp: Double = 30
    
    var body: some View {
        ZStack {
            // Background: Camera preview if in camera mode
            if appState == .camera {
                CameraView { image in
                    capturedImage = image
                    appState = .processing
                    isProcessing = true
                    // Run segmentation using the modularized method
                    ImageSegmentation.segmentObject(in: image) { result in
                        segmentedImage = result
                        isProcessing = false
                        appState = .playback
                    }
                }
                .edgesIgnoringSafeArea(.all)
            } else if let image = segmentedImage, appState == .playback {
                ZStack {
                    Color(red: 0.85, green: 0.75, blue: 0.95).edgesIgnoringSafeArea(.all)
                    if let cropped = cropImage(image, by: 8) {
                        Cutout3DView(
                            image: cropped,
                            pitch: motionManager.pitch,
                            roll: motionManager.roll,
                            yaw: motionManager.yaw,
                            cutoutRotationClamp: cutoutRotationClamp
                        )
                    } else {
                        Cutout3DView(
                            image: image,
                            pitch: motionManager.pitch,
                            roll: motionManager.roll,
                            yaw: motionManager.yaw,
                            cutoutRotationClamp: cutoutRotationClamp
                        )
                    }
                }
                .onAppear {
                    // Generate melody when entering playback, but do not auto-play
                    if let img = segmentedImage {
                        let melody = sonification.generateMelody(from: img)
                        currentMelody = melody
                    }
                }
                .onDisappear {
                    melodyPlayer.stop()
                    isPlaying = false
                    previewTimer?.invalidate()
                    previewProgress = 0.0
                }
            } else if appState == .processing {
                Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
                ProgressView("Processing...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .scaleEffect(1.5)
            } else {
                Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
            }
            
        VStack {
                Spacer()
                // Floating pill container
                VStack(spacing: 10) {
                    
                    //Preview Pill
                    if appState == .playback, hasRecording, let recordingURL = melodyPlayer.getRecordingURL() {
                        
                        HStack {
                            Spacer()
                            HStack(spacing: 24) {
                                Button(action: {
                                    // Share via share sheet
                                    shareURL = recordingURL
                                    showShareSheet = true
                                }) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.green))
                                }
                                // Preview play button with progress ring
                                ZStack {
                                    // Progress ring outside the button
                                    Circle()
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 10)
                                        .frame(width: 64, height: 64) // Larger than button
                                    Circle()
                                        .trim(from: 0, to: previewProgress)
                                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                        .frame(width: 64, height: 64)
                                        .animation(.linear(duration: 0.1), value: previewProgress)
                                    Button(action: {
                                        if isPreviewing {
                                            audioPlayer?.stop()
                                            isPreviewing = false
                                            previewTimer?.invalidate()
                                            previewProgress = 0.0
                                        } else {
                                            do {
                                                audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
                                                audioPlayer?.play()
                                                isPreviewing = true
                                                previewProgress = 0.0
                                                previewTimer?.invalidate()
                                                previewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                                                    if let player = audioPlayer {
                                                        previewProgress = min(player.currentTime / player.duration, 1.0)
                                                        if !player.isPlaying {
                                                            isPreviewing = false
                                                            previewTimer?.invalidate()
                                                            previewProgress = 0.0
                                                        }
                                                    }
                                                }
                                            } catch {
                                                print("Preview error: \(error)")
                                            }
                                        }
                                    }) {
                                        Image(systemName: isPreviewing ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(8)
                                            .background(Circle().fill(Color.white))
                                    }
                                    .frame(width: 48, height: 48)
                                }
                                Button(action: {
                                    //TODO: Navigate to share online
                                }) {
                                    Image(systemName: "network")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Circle().fill(Color.blue))
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 10)
                            Spacer()
                        }
                        
                    }

                    // Main Pill (action buttons)
                    HStack {
                        Spacer()
                        HStack(spacing: 24) {
                            // Back button (appears as needed)
                            if appState != .camera {
                                Button(action: {
                                    appState = .camera
                                    capturedImage = nil
                                    segmentedImage = nil
                                    melodyPlayer.stop()
                                    isPlaying = false
                                    isRecording = false
                                    hasRecording = false
                                    isPreviewing = false
                                    audioPlayer?.stop()
                                    audioPlayer = nil
                                }) {
                                    Image(systemName: "chevron.left")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                            }
                            // Main action buttons for playback
                            if appState == .playback {
                                // Stop button (left)
                                Button(action: {
                                    melodyPlayer.kill()
                                    isPlaying = false
                                }) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(16)
                                        .background(Circle().fill(Color.black))
                                }
                                // Play/Pause button (center)
                                Button(action: {
                                    if isPlaying {
                                        melodyPlayer.stop()
                                    } else {
                                        melodyPlayer.play(notes: currentMelody)
                                    }
                                    isPlaying.toggle()
                                }) {
                                    Image(systemName: hasRecording ? "play.circle" : (isPlaying ? "pause.circle" : "play.circle"))
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(isPlaying ? .white : .green)
                                        .padding()
                                        .background(Circle().fill(isPlaying ? Color.red : Color.white))
                                }
                                .disabled(hasRecording) // Disable when preview UI is visible
                                .opacity(hasRecording ? 0.5 : 1.0) // Grey out when preview UI is visible
                                // Record/Trash button (right)
                                if hasRecording {
                                    Button(action: {
                                        showDeleteConfirm = true
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 32, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(16)
                                            .background(Circle().fill(Color.red))
                                    }
                                    .confirmationDialog("Clear Recording? (Saved files will not be deleted)", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                                        Button("Clear", role: .destructive) {
                                            hasRecording = false
                                            isPreviewing = false
                                            audioPlayer?.stop()
                                            audioPlayer = nil
                                            // TODO: Delete recording logic (remove file if needed)
                                        }
                                        Button("Cancel", role: .cancel) {}
                                    }
                                } else {
                                    Button(action: {
                                        isRecording.toggle()
                                        if isRecording {
                                            melodyPlayer.startRecording()
                                            recordingProgress = 0.0
                                            recordingTimer?.invalidate()
                                            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                                                recordingProgress += 0.1 / maxRecordingDuration
                                                if recordingProgress >= 1.0 {
                                                    // Auto-stop recording at 30 seconds
                                                    isRecording = false
                                                    melodyPlayer.stopRecording()
                                                    melodyPlayer.kill()
                                                    recordingTimer?.invalidate()
                                                    recordingProgress = 0.0
                                                    hasRecording = melodyPlayer.getRecordingURL() != nil
                                                }
                                            }
                                        } else {
                                            melodyPlayer.stopRecording()
                                            melodyPlayer.kill()
                                            recordingTimer?.invalidate()
                                            recordingProgress = 0.0
                                            hasRecording = melodyPlayer.getRecordingURL() != nil
                                            print("hasRecording: \(hasRecording)")
                                            print("Recording URL: \(String(describing: melodyPlayer.getRecordingURL()))")
                                        }
                                    }) {
                                        ZStack {
                                            // Recording progress ring
                                            Circle()
                                                .stroke(Color.red.opacity(0.3), lineWidth: 10)
                                                .frame(width: 56, height: 56)
                                            Circle()
                                                .trim(from: 0, to: recordingProgress)
                                                .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                                .rotationEffect(.degrees(-90))
                                                .frame(width: 56, height: 56)
                                                .animation(.linear(duration: 0.1), value: recordingProgress)
                                            Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                                                .font(.system(size: 32, weight: .bold))
                                                .foregroundColor(.red)
                                                .padding(16)
                                                .background(Circle().fill(Color.white))
                                        }
                                    }
                                }
                            }
                            // Main action button
                            if appState == .camera {
                                Button(action: {
                                    // Trigger photo capture via notification
                                    NotificationCenter.default.post(name: .capturePhoto, object: nil)
                                }) {
                                    Image(systemName: "circle")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Circle().fill(Color.accentColor))
                                }
                            } else if appState == .recording {
                                Button(action: {
                                    // Stop recording
                                    appState = .playback
                                }) {
                                    Image(systemName: "stop.circle")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Circle().fill(Color.red))
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(radius: 10)
                        Spacer()
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showShareSheet, content: {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        })
        .sheet(isPresented: $showDocumentPicker, content: {
            if let url = documentPickerURL {
                DocumentPicker(url: url)
            }
        })
        .animation(.easeInOut, value: appState)
        .onAppear {
            motionManager.startUpdates()
        }
        .onDisappear {
            motionManager.stopUpdates()
            previewTimer?.invalidate()
            previewProgress = 0.0
        }
        .onChange(of: motionManager.pitch) { oldPitch, newPitch in
            // Map pitch (-π/4 to π/4) to reverb mix (0 to 1)
            let minPitch = -Double.pi / 4
            let maxPitch = Double.pi / 4
            let clampedPitch = min(max(newPitch, minPitch), maxPitch)
            let mix = AUValue((clampedPitch - minPitch) / (maxPitch - minPitch))
            melodyPlayer.setReverbMix(mix)
        }
        .onChange(of: motionManager.roll) { oldRoll, newRoll in
            // Map roll (-π/2 to π/2) to playback speed (2.0 to 0.5, inverted)
            let minRoll = -Double.pi / 2
            let maxRoll = Double.pi / 2
            let clampedRoll = min(max(newRoll, minRoll), maxRoll)
            let norm = abs(clampedRoll) / (maxRoll)
            let speed = 2.0 - 1.5 * norm // Inverted: flat = fast, tilt = slow
            melodyPlayer.setPlaybackSpeed(speed)
        }
    }
    
    // MARK: - Segmentation Logic
}

extension ContentView {
    // Existing preview initializer
    init(appState: AppFlowState, segmentedImage: UIImage? = nil) {
        self._appState = State(initialValue: appState)
        self._segmentedImage = State(initialValue: segmentedImage)
    }
    // New preview initializer for post-recording state
    init(appState: AppFlowState, segmentedImage: UIImage?, hasRecording: Bool, dummyRecordingURL: URL?) {
        self._appState = State(initialValue: appState)
        self._segmentedImage = State(initialValue: segmentedImage)
        self._hasRecording = State(initialValue: hasRecording)
        let melodyPlayer = MelodyPlayer()
        melodyPlayer.previewRecordingURL = dummyRecordingURL // Use the property, not an override
        self._melodyPlayer = StateObject(wrappedValue: melodyPlayer)
    }
}

// Real camera view using UIViewControllerRepresentable
struct CameraView: UIViewControllerRepresentable {
    var onPhotoCapture: (UIImage) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let vc = CameraViewController()
        vc.onPhotoCapture = onPhotoCapture
        context.coordinator.setup(vc: vc)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
    
    class Coordinator: NSObject {
        let parent: CameraView
        init(parent: CameraView) { self.parent = parent }
        func setup(vc: CameraViewController) {
            NotificationCenter.default.addObserver(forName: .capturePhoto, object: nil, queue: .main) { _ in
                vc.capturePhoto()
            }
        }
    }
}

class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var photoOutput: AVCapturePhotoOutput?
    var onPhotoCapture: ((UIImage) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.addInput(input)
        let output = AVCapturePhotoOutput()
        session.addOutput(output)
        self.photoOutput = output
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        self.previewLayer = preview
        self.captureSession = session
        session.startRunning()
    }
    
    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput?.capturePhoto(with: settings, delegate: self)
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        onPhotoCapture?(image)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}

extension Notification.Name {
    static let capturePhoto = Notification.Name("capturePhoto")
}

// ShareSheet helper
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// DocumentPicker helper
import UniformTypeIdentifiers
struct DocumentPicker: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

#if DEBUG
import SwiftUI

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentViewPreviewWrapper(appState: .camera)
                .previewDisplayName("Camera")
            ContentViewPreviewWrapper(appState: .processing)
                .previewDisplayName("Processing")
            ContentViewPreviewWrapper(appState: .playback, withImage: true)
                .previewDisplayName("Playback")
            ContentViewPreviewWrapper(appState: .playback, withImage: true, hasRecording: true)
                .previewDisplayName("Post-Recording (After Stop)")
            ContentViewPreviewWrapper(appState: .recording)
                .previewDisplayName("Recording")
        }
    }
}

private struct ContentViewPreviewWrapper: View {
    let appState: AppFlowState
    let segmentedImage: UIImage?
    let hasRecording: Bool
    let dummyRecordingURL: URL?
    
    init(appState: AppFlowState, withImage: Bool = false, hasRecording: Bool = false) {
        self.appState = appState
        if withImage {
            let config = UIImage.SymbolConfiguration(pointSize: 200)
            self.segmentedImage = UIImage(systemName: "person.crop.square", withConfiguration: config)
        } else {
            self.segmentedImage = nil
        }
        self.hasRecording = hasRecording
        // Always use a hardcoded dummy URL for preview recording
        self.dummyRecordingURL = URL(fileURLWithPath: "/tmp/dummy.m4a")
    }
    
    var body: some View {
        if hasRecording {
            ContentView(appState: .playback, segmentedImage: segmentedImage, hasRecording: true, dummyRecordingURL: dummyRecordingURL)
        } else {
            ContentView(appState: appState, segmentedImage: segmentedImage)
        }
    }
}
#endif

#Preview {
    ContentView()
}
