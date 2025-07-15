//
//  ContentView.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/14/25.
//

import SwiftUI
import AVFoundation
import Vision

// App states
enum AppFlowState {
    case camera
    case processing
    case playback
    case recording
}

struct ContentView: View {
    @State private var appState: AppFlowState = .camera // Start with camera open
    @State private var capturedImage: UIImage? = nil
    @State private var segmentedImage: UIImage? = nil
    @State private var isProcessing: Bool = false
    
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
            } else if appState == .processing {
                Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
                ProgressView("Processing...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .foregroundColor(.white)
                    .scaleEffect(1.5)
            } else {
                Color.black.opacity(0.95).edgesIgnoringSafeArea(.all)
            }
            
            // Floating pill container
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    HStack(spacing: 24) {
                        // Back button (appears as needed)
                        if appState != .camera {
                            Button(action: {
                                appState = .camera
                                capturedImage = nil
                                segmentedImage = nil
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
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
                        } else if appState == .playback {
                            Button(action: {
                                // Placeholder for record action
                                appState = .recording
                            }) {
                                Image(systemName: "record.circle")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Circle().fill(Color.white))
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
        }
        .animation(.easeInOut, value: appState)
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

#Preview {
    ContentView()
}
