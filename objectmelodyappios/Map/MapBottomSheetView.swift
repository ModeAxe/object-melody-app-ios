import SwiftUI
import AudioKit
import AVFoundation

// MARK: - Color Scheme Constants
struct BottomSheetColors {
    static let background = Color(.systemBackground)
    static let secondaryBackground = Color(.systemGray6)
    static let accent = Color.blue
    static let accentLight = Color.blue.opacity(0.3)
    static let text = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let success = Color.green
    static let error = Color.red
    static let warning = Color.orange
    static let cardBackground = Color(.systemGray5)
    static let shadow = Color.black.opacity(0.1)
}

enum BottomSheetMode {
    case list
    case detail
    case add
}

var cardCornerRadius: CGFloat = 12
let cardWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.4
let cardHeight = cardWidth * 1.4

struct MapBottomSheetView: View {
    let traces: [TraceAnnotation]
    let selectedTrace: TraceAnnotation?
    let mode: BottomSheetMode
    let onTraceSelected: (TraceAnnotation) -> Void
    let onBackToList: () -> Void
    let onExpandSheet: () -> Void
    
    // Add mode parameters
    let cutoutImage: UIImage?
    let objectName: Binding<String>
    let isUploading: Bool
    let uploadProgress: Double
    let onAddTrace: () -> Void
    let hasSelectedLocation: Bool
    
    // Bottom sheet state
    let isExpanded: Bool
    
    @StateObject private var audioPlayer = AudioPlayer()
    
    var body: some View {
        VStack(spacing: 0) {
            // Toggle Button
            Button(action: {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .soft)
                impactFeedback.impactOccurred()
                
                // This will be handled by the parent view
                NotificationCenter.default.post(name: NSNotification.Name("ToggleBottomSheet"), object: nil)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(BottomSheetColors.secondaryBackground)
                .cornerRadius(20)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
            
            // Content
            if mode == .list {
                listView
            } else if mode == .detail {
                detailView
            } else if mode == .add {
                addView
            }
        }
        .background(BottomSheetColors.background)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: BottomSheetColors.shadow, radius: 10, x: 0, y: -5)
    }
    
    private var listView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Traces near you")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(BottomSheetColors.text)
                Spacer()
                Text("\(traces.count)")
                    .font(.caption)
                    .foregroundColor(BottomSheetColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BottomSheetColors.cardBackground)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            
            // Traces List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(traces) { trace in
                        TraceListItemView(trace: trace) {
                            onTraceSelected(trace)
                            // Expand the bottom sheet when a trace is selected
                            if !isExpanded {
                                onExpandSheet()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    private var detailView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with back button
            HStack {
                Button(action: onBackToList) {
                                            HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(BottomSheetColors.accent)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            if let trace = selectedTrace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Trace Image
                        ZStack {
                            RoundedRectangle(cornerRadius: cardCornerRadius)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            //magic number here i know i know --will change it eventually I think. maybe
                                            getColorForSoundFont(Int.random(in: 0...9))[1],
                                            getColorForSoundFont(Int.random(in: 0...9))[0]
                                        ]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                            AsyncImage(url: trace.imageURL) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: cardWidth - 32, height: cardWidth - 32)
                                    .shadow(color: Color.white.opacity(1), radius: 8, x: 0, y: 0)
                            } placeholder : {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 200)
                                    .cornerRadius(12)
                                    .overlay(
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    )
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        
                        // Trace Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                                .foregroundColor(BottomSheetColors.textSecondary)
                            Text(trace.name)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(BottomSheetColors.text)
                        }
                        
                        // Audio Player
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audio")
                                .font(.headline)
                                .foregroundColor(BottomSheetColors.textSecondary)
                            
                            HStack(spacing: 16) {
                                Button(action: togglePlayback) {
                                    if audioPlayer.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(1.2)
                                    } else if audioPlayer.error != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(BottomSheetColors.error)
                                    } else {
                                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(BottomSheetColors.accent)
                                    }
                                }
                                .disabled(audioPlayer.isLoading || audioPlayer.error != nil)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if audioPlayer.isLoading {
                                        Text("Loading audio...")
                                            .font(.subheadline)
                                            .foregroundColor(BottomSheetColors.textSecondary)
                                    } else if let error = audioPlayer.error {
                                        Text("Error loading audio")
                                            .font(.subheadline)
                                            .foregroundColor(BottomSheetColors.error)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(BottomSheetColors.error)
                                    } else {
                                        Text(audioPlayer.isPlaying ? "Playing" : "Tap to play")
                                            .font(.subheadline)
                                            .foregroundColor(BottomSheetColors.textSecondary)
                                        
                                        if let duration = audioPlayer.duration {
                                            Text(formatTime(duration))
                                                .font(.caption)
                                                .foregroundColor(BottomSheetColors.textSecondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(
                                GeometryReader { geometry in
                                    ZStack {
                                        // Full background
                                        Rectangle()
                                            .fill(BottomSheetColors.secondaryBackground)
                                        // Progress background
                                        Rectangle()
                                            .fill(BottomSheetColors.accentLight)
                                            .frame(width: getProgressWidth(containerWidth: geometry.size.width))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            )
                            .cornerRadius(12)
                        }
                        
                        // Timestamp
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Created")
                                .font(.headline)
                                .foregroundColor(BottomSheetColors.textSecondary)
                            Text(formatDate(trace.timestamp))
                                .font(.subheadline)
                                .foregroundColor(BottomSheetColors.text)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            if let trace = selectedTrace {
                audioPlayer.stop() // Reset state before loading new audio
                audioPlayer.loadAudio(from: trace.audioURL)
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }
    
    private var addView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Add Your Trace")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(BottomSheetColors.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Preview cutout
                    if let cutout = cutoutImage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(.headline)
                                .foregroundColor(BottomSheetColors.textSecondary)
                            
                            Image(uiImage: cutout)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(12)
                        }
                    }
                    
                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name your trace")
                            .font(.headline)
                            .foregroundColor(BottomSheetColors.textSecondary)
                        
                        TextField("Enter a name...", text: objectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(isUploading)
                    }
                    
                    // Upload button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upload")
                            .font(.headline)
                            .foregroundColor(BottomSheetColors.textSecondary)
                        
                        // Validation messages
                        if objectName.wrappedValue.isEmpty {
                            Text("Please enter a name for your trace")
                                .font(.caption)
                                .foregroundColor(BottomSheetColors.error)
                        }
                        
                        if !hasSelectedLocation {
                            Text("Tap the map to select a location")
                                .font(.caption)
                                .foregroundColor(BottomSheetColors.warning)
                        }
                        
                        Button(action: onAddTrace) {
                            HStack {
                                if isUploading {
                                    ProgressView(value: uploadProgress)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                    Text("\(Int(uploadProgress * 100))%")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "cloud.upload")
                                    Text("Add to Map")
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(isUploading ? BottomSheetColors.textSecondary : BottomSheetColors.accent)
                            .cornerRadius(12)
                        }
                        .disabled(objectName.wrappedValue.isEmpty || isUploading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
    
    
    private func togglePlayback() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
    }
    
    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getProgressWidth(containerWidth: CGFloat) -> CGFloat {
        guard let duration = audioPlayer.duration, duration > 0 else { return 0 }
        let progress = audioPlayer.currentTime / duration
        return containerWidth * progress
    }
}
    
// MARK: - Trace List Item View
struct TraceListItemView: View {
    let trace: TraceAnnotation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Trace Image
                AsyncImage(url: trace.imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(BottomSheetColors.cardBackground)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(BottomSheetColors.textSecondary)
                        )
                }
                
                // Trace Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(trace.name)
                        .font(.headline)
                        .foregroundColor(BottomSheetColors.text)
                        .lineLimit(1)
                    
                    Text(formatDate(trace.timestamp))
                        .font(.caption)
                        .foregroundColor(BottomSheetColors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(BottomSheetColors.textSecondary)
                    .font(.caption)
            }
            .padding()
            .background(BottomSheetColors.secondaryBackground)
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Audio Player
class AudioPlayer: ObservableObject {
    private var player: AVAudioPlayer?
    @Published var duration: TimeInterval?
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var isLoading = false
    @Published var error: String?
    private var progressTimer: Timer?
    
    func loadAudio(from url: URL) {
        print("🎵 Loading audio from URL: \(url)")
        isLoading = true
        error = nil
        
        // Download the audio file first
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("🎵 Network error loading audio: \(error)")
                    self?.error = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    print("🎵 No data received from URL")
                    self?.error = "No audio data received"
                    return
                }
                
                print("🎵 Received \(data.count) bytes of audio data")
                
                // Create a temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio_\(UUID().uuidString).m4a")
                
                do {
                    try data.write(to: tempURL)
                    print("🎵 Saved audio to temp file: \(tempURL)")
                    
                    self?.player = try AVAudioPlayer(contentsOf: tempURL)
                    self?.player?.prepareToPlay()
                    self?.duration = self?.player?.duration
                    print("🎵 Audio player created successfully, duration: \(self?.duration ?? 0)")
                    
                } catch {
                    print("🎵 Error creating audio player: \(error)")
                    self?.error = "Audio format error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func play() {
        player?.play()
        isPlaying = true
        startProgressTimer()
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }
    
    func stop() {
        player?.stop()
        player?.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopProgressTimer()
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            self.currentTime = player.currentTime
            
            // Check if audio has finished playing
            if !player.isPlaying && self.isPlaying {
                self.isPlaying = false
            }
        }
    }
    
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
} 
