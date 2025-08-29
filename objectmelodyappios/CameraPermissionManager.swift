import AVFoundation
import UIKit

class CameraPermissionManager: ObservableObject {
    @Published var cameraPermissionStatus: AVAuthorizationStatus = .notDetermined
    @Published var showPermissionAlert = false
    @Published var showSettingsAlert = false
    
    init() {
        checkCameraPermission()
    }
    
    func checkCameraPermission() {
        cameraPermissionStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraPermissionStatus = granted ? .authorized : .denied
                if !granted {
                    self?.showPermissionAlert = true
                }
            }
        }
    }
    
    func openSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    var permissionMessage: String {
        switch cameraPermissionStatus {
        case .notDetermined:
            return "Camera access is needed to take photos of objects and turn them into melodies."
        case .denied:
            return "Camera access was denied. You can enable it in Settings to use this app."
        case .restricted:
            return "Camera access is restricted. Check your device settings."
        case .authorized:
            return ""
        @unknown default:
            return "Camera access is needed to use this app."
        }
    }
    
    var shouldShowPermissionRequest: Bool {
        return cameraPermissionStatus == .notDetermined
    }
    
    var shouldShowSettingsPrompt: Bool {
        return cameraPermissionStatus == .denied || cameraPermissionStatus == .restricted
    }
    
    var canAccessCamera: Bool {
        return cameraPermissionStatus == .authorized
    }
} 