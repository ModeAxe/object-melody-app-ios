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
import CoreMotion
import UIKit

// App states / phases
enum AppFlowState {
    case camera
    case processing
    case playback
    case recording
    case segmentationFailed
    case cameraPermissionDenied
}

enum MapDestination: Hashable {
    case browse
    case add(recordingURL: URL, cutoutImage: UIImage)
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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
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
    
    // 1. Add state for preview progress
    @State private var previewProgress: Double = 0.0
    @State private var previewTimer: Timer? = nil
    
    // Add recording progress state
    @State private var recordingProgress: Double = 0.0
    @State private var recordingTimer: Timer? = nil
    let maxRecordingDuration: Double = 30.0 // 30 seconds
    
    // Clamp value for cutout rotation (in degrees)
    let cutoutRotationClamp: Double = 30
    
    @State private var segmentationManager = SegmentationManager(strategy: VNMaskSegmentation())
    
    @State private var showMapBrowse = false
    @State private var showMapAdd = false
    @State private var mapDestination: MapDestination? = nil
    @State private var userLocation: CLLocationCoordinate2D? = nil
    @State private var currentSoundFontColor: [Color] = [.blue, .yellow]
    @State private var isTransitioningColor: Bool = false
    
    // Camera permission handling
    @StateObject private var cameraPermissionManager = CameraPermissionManager()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera feed - only show if permission granted
                if cameraPermissionManager.canAccessCamera {
                    CameraView { image in
                        capturedImage = image
                        appState = .processing
                        isProcessing = true
                        // Run segmentation using the modularized method
                        segmentationManager.segmentObject(in: image) { result in
                            if let segmentedResult = result {
                                segmentedImage = segmentedResult
                                isProcessing = false
                                appState = .playback
                            } else {
                                // Segmentation failed - show retry prompt
                                isProcessing = false
                                appState = .segmentationFailed
                            }
                        }
                    }.blur(radius: appState == .camera ? 0 : 15)
                    .edgesIgnoringSafeArea(.all)
                } else {
                    // Permission denied state - show placeholder
                    Color.black.edgesIgnoringSafeArea(.all)
                }
                
                // Overlay content based on app state
                if !cameraPermissionManager.canAccessCamera {
                    // Camera permission denied state
                    VStack(spacing: 30) {
                        Spacer()
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.white)
                        
                        Text("Camera Access Required")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text(cameraPermissionManager.permissionMessage)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        if cameraPermissionManager.shouldShowPermissionRequest {
                            Button(action: {
                                cameraPermissionManager.requestCameraPermission()
                            }) {
                                Text("Allow Camera Access")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(25)
                            }
                        } else if cameraPermissionManager.shouldShowSettingsPrompt {
                            Button(action: {
                                cameraPermissionManager.openSettings()
                            }) {
                                Text("Open Settings")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 12)
                                    .background(Color.blue)
                                    .cornerRadius(25)
                            }
                        }
                        
                        Spacer()
                    }
                } else if appState == .camera {
                    // Camera state - no additional overlay needed
                    // Removed EmptyView() to prevent layer conflicts
                } else if let image = segmentedImage, appState == .playback {
                    // Playback state - show cutout over camera feed
                    ZStack {
                        if let cropped = cropImage(image, by: 8) {
                            Cutout3DView(
                                image: cropped,
                                pitch: motionManager.pitch,
                                roll: motionManager.roll,
                                yaw: motionManager.yaw,
                                cutoutRotationClamp: cutoutRotationClamp,
                                backgroundColor: currentSoundFontColor,
                                isTransitioning: isTransitioningColor
                            )
                        } else {
                            Cutout3DView(
                                image: image,
                                pitch: motionManager.pitch,
                                roll: motionManager.roll,
                                yaw: motionManager.yaw,
                                cutoutRotationClamp: cutoutRotationClamp,
                                backgroundColor: currentSoundFontColor,
                                isTransitioning: isTransitioningColor
                            )
                        }
                        
                    }
                    .onAppear {
                        // Generate melody when entering playback, but do not auto-play
                        if let img = segmentedImage {
                            let melody = sonification.generateMelody(from: img)
                            currentMelody = melody
                        }
                        
                        // Initialize sound font color
                        currentSoundFontColor = getColorForSoundFont(melodyPlayer.getCurrentSoundFontIndex())
                    }
                    .onDisappear {
                        melodyPlayer.stop()
                        isPlaying = false
                        previewTimer?.invalidate()
                        previewProgress = 0.0
                    }.gesture(DragGesture(minimumDistance: 20, coordinateSpace: .global).onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = value.translation.height
                        
                        if abs(horizontalAmount) > abs(verticalAmount) {
                            print(horizontalAmount < 0 ? "left swipe" : "right swipe")
                        } else {
                            if (verticalAmount < 0) {
                                print("Swipe Up")
                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                // Start color transition
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isTransitioningColor = true
                                }
                                
                                melodyPlayer.changeSoundFont(delta: 1)
                                
                                // Update color after transition
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    currentSoundFontColor = getColorForSoundFont(melodyPlayer.getCurrentSoundFontIndex())
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTransitioningColor = false
                                    }
                                }
                            }
                            else {
                                print("Swipe Down")
                                // Haptic feedback
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                                
                                // Start color transition
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isTransitioningColor = true
                                }
                                
                                melodyPlayer.changeSoundFont(delta: -1)
                                
                                // Update color after transition
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    currentSoundFontColor = getColorForSoundFont(melodyPlayer.getCurrentSoundFontIndex())
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isTransitioningColor = false
                                    }
                                }
                            }
                            //print(verticalAmount < 0 ? "up swipe" : "down swipe")
                        }
                    })
                } else if appState == .processing {
                    // Processing state - show overlay over camera feed
                    Color.black.opacity(1).edgesIgnoringSafeArea(.all)
                    ProgressView("Tracing...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                        .scaleEffect(1.5)
                } else if appState == .segmentationFailed {
                    // Segmentation failed state - show retry prompt
                    Color.black.opacity(0.8).edgesIgnoringSafeArea(.all)
                    VStack(spacing: 24) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        
                        Text("Object Not Found")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Consider moving closer to the object and try again")
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button(action: {
                            // Reset and go back to camera
                            appState = .camera
                            capturedImage = nil
                            segmentedImage = nil
                        }) {
                            Text("Try Again")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                    }
                }
                
                // UI elements (pills, buttons) always on top
        VStack {
                    HStack {
                        Spacer()
                        Button(action: { melodyPlayer.kill(); mapDestination = .browse }) {
                            Image(systemName: "map")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        .padding(.top, 40)
                        .padding(.trailing, 24)
                    }
                    Spacer()
                    // Floating pill container
                    VStack(spacing: 10) {
                        
                        //Preview Pill
                        if appState == .playback, hasRecording, let recordingURL = melodyPlayer.getRecordingURL() {
                            
                            PreviewPillView(
                                hasRecording: hasRecording,
                                recordingURL: recordingURL,
                                isPreviewing: isPreviewing,
                                previewProgress: previewProgress,
                                onShare: {
                                    shareURL = recordingURL
                                    showShareSheet = true
                                },
                                onPreviewPlay: {
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
                                },
                                onNetwork: {
                                    audioPlayer?.pause()
                                    if let url = melodyPlayer.getRecordingURL(), let img = segmentedImage {
                                        mapDestination = .add(recordingURL: url, cutoutImage: img)
                                    }
                                }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Main Pill
                        MainPillView(
                            appState: appState,
                            isPlaying: isPlaying,
                            hasRecording: hasRecording,
                            isRecording: isRecording,
                            recordingProgress: recordingProgress,
                            showDeleteConfirm: $showDeleteConfirm,
                            onBack: {
                                appState = .camera
                                capturedImage = nil
                                segmentedImage = nil
                                melodyPlayer.kill()
                                isPlaying = false
                                isRecording = false
                                hasRecording = false
                                isPreviewing = false
                                audioPlayer?.stop()
                                audioPlayer = nil
                            },
                            onStop: {
                                melodyPlayer.kill()
                                isPlaying = false
                            },
                            onPlayPause: {
                                if isPlaying {
                                    melodyPlayer.stop()
                                } else {
                                    melodyPlayer.play(notes: currentMelody)
                                }
                                isPlaying.toggle()
                            },
                            onRecord: {
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
                            },
                            onDelete: {
                                hasRecording = false
                                isPreviewing = false
                                audioPlayer?.stop()
                                audioPlayer = nil
                                // Optionally: melodyPlayer.deleteRecordingFile() if you want to remove the file
                            },
                            onCamera: {
                                NotificationCenter.default.post(name: .capturePhoto, object: nil)
                            },
                            onStopRecording: {
                                appState = .playback
                            }
                        )
                    }
                    .animation(.easeInOut, value: hasRecording)
                    .padding(.bottom, 40)
                }
            }
            .navigationDestination(item: $mapDestination) { dest in
                switch dest {
                case .browse:
                    MapView(isAddMode: false, recordingURL: nil, cutoutImage: nil, initialLocation: userLocation)
                case .add(let url, let image):
                    MapView(isAddMode: true, recordingURL: url, cutoutImage: image, initialLocation: userLocation)
                }
            }
        }
        .sheet(isPresented: $showShareSheet, content: {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        })
        .sheet(isPresented: $showOnboarding) {
            OnboardingWelcomeSheetView()
                .onDisappear {
                    hasCompletedOnboarding = true
                }
                .interactiveDismissDisabled()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        // Removed zIndex to prevent layer conflicts
        .animation(.easeInOut, value: appState)
        .onAppear {
            motionManager.startUpdates()
            
            // Check camera permissions
            cameraPermissionManager.checkCameraPermission()
            
            // Show onboarding on first launch with slight delay to avoid conflicts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            
            // Fetch user location in background when app opens
            Task {
                if let location = await fetchUserLocation() {
                    userLocation = location
                }
            }
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
        .onChange(of: motionManager.yaw) { oldYaw, newYaw in
            let minDelay: AUValue = 0.0  // Changed from 0.1 to 0.0 for full range
            let maxDelay: AUValue = 1.0
            let normalizedYaw = (newYaw + .pi) / (2 * .pi) // Map -π...π to 0...1
            let delayMix = minDelay + (maxDelay - minDelay) * AUValue(normalizedYaw)
            // Clamp to ensure valid range
            let clampedDelayMix = max(0.0, min(1.0, delayMix))
            melodyPlayer.setDelayMix(clampedDelayMix)
        }
    }
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
        
        // Check camera permission before setting up
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard authStatus == .authorized else {
            print("Camera permission not granted: \(authStatus.rawValue)")
            return
        }
        
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { 
            print("Failed to setup camera input")
            return 
        }
        
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
        
        DispatchQueue.global(qos: .background).async {
            session.startRunning()
        }
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
