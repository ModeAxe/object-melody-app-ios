//
//  ContentView.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/14/25.
//

import SwiftUI
import AVFoundation
import Vision

// Add these imports for sonification and playback
import AudioKit
import AudioKitEX
import CoreMotion

// App states
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
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.pitch = motion.attitude.pitch
            self.roll = motion.attitude.roll
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
                        Image(uiImage: cropped)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.5, maxHeight: UIScreen.main.bounds.height * 0.5)
                            .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
                            .padding()
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: UIScreen.main.bounds.width * 0.5, maxHeight: UIScreen.main.bounds.height * 0.5)
                            .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
                            .padding()
                    }
                }
                .onAppear {
                    if let img = segmentedImage {
                        let melody = sonification.generateMelody(from: img)
                        currentMelody = melody
                    }
                }
                .onDisappear {
                    melodyPlayer.stop()
                    isPlaying = false
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
                // Save/Share buttons above the pill if hasRecording
                if appState == .playback, hasRecording, let recordingURL = melodyPlayer.getRecordingURL() {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Button(action: {
                                // Show document picker to save file
                                documentPickerURL = recordingURL
                                showDocumentPicker = true
                            }) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.green))
                            }
                            Button(action: {
                                // Share via share sheet
                                shareURL = recordingURL
                                showShareSheet = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.blue))
                            }
                        }
                        .padding(.bottom, 40)
                        .padding(.trailing, 24)
                    }
                }
                // Floating pill container
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
                                Image(systemName: isPlaying ? "pause.circle" : "play.circle")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(isPlaying ? .white : .green)
                                    .padding()
                                    .background(Circle().fill(isPlaying ? Color.red : Color.white))
                            }
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
                                .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                                    Button("Delete", role: .destructive) {
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
                                    } else {
                                        melodyPlayer.stopRecording()
                                        hasRecording = melodyPlayer.getRecordingURL() != nil
                                        print("hasRecording: \(hasRecording)")
                                        print("Recording URL: \(String(describing: melodyPlayer.getRecordingURL()))")
                                    }
                                }) {
                                    Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                                        .font(.system(size: 32, weight: .bold))
                                        .foregroundColor(.red)
                                        .padding(16)
                                        .background(Circle().fill(Color.white))
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
                .padding(.bottom, 40)
            }
            // Playback preview button (floating, only if hasRecording)
            if appState == .playback, hasRecording, let recordingURL = melodyPlayer.getRecordingURL() {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            if isPreviewing {
                                audioPlayer?.stop()
                                isPreviewing = false
                            } else {
                                do {
                                    audioPlayer = try AVAudioPlayer(contentsOf: recordingURL)
                                    audioPlayer?.play()
                                    isPreviewing = true
                                } catch {
                                    print("Preview error: \(error)")
                                }
                            }
                        }) {
                            Image(systemName: isPreviewing ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.orange)
                                .padding(12)
                                .background(Circle().fill(Color.white))
                        }
                    }
                    .padding(.bottom, 180)
                    .padding(.trailing, 24)
                }
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

// Helper to crop a UIImage by a number of pixels from each edge
func cropImage(_ image: UIImage, by pixels: CGFloat) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    let width = CGFloat(cgImage.width)
    let height = CGFloat(cgImage.height)
    let cropRect = CGRect(x: pixels, y: pixels, width: width - 2 * pixels, height: height - 2 * pixels)
    guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
    return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
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

#Preview {
    ContentView()
}
