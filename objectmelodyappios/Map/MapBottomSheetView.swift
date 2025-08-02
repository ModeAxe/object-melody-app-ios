import SwiftUI
import AudioKit
import AVFoundation

enum BottomSheetMode {
    case list
    case detail
    case add
}

struct MapBottomSheetView: View {
    let traces: [TraceAnnotation]
    let selectedTrace: TraceAnnotation?
    let mode: BottomSheetMode
    let onTraceSelected: (TraceAnnotation) -> Void
    let onBackToList: () -> Void
    
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
    @State private var isPlaying = false
    
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
                .background(Color(.systemGray6))
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
        .background(Color(.systemBackground))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
    }
    
    private var listView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Traces near you")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Text("\(traces.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            
            // Traces List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(traces) { trace in
                        TraceListItemView(trace: trace) {
                            onTraceSelected(trace)
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
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                Text("Trace Details")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            if let trace = selectedTrace {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Trace Image
                        AsyncImage(url: trace.imageURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(12)
                        } placeholder: {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .frame(height: 200)
                                .cornerRadius(12)
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                )
                        }
                        
                        // Trace Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(trace.name)
                                .font(.title3)
                                .fontWeight(.medium)
                        }
                        
                        // Audio Player
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Audio")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 16) {
                                Button(action: togglePlayback) {
                                    if audioPlayer.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .scaleEffect(1.2)
                                    } else if audioPlayer.error != nil {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(.red)
                                    } else {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 44))
                                            .foregroundColor(.blue)
                                    }
                                }
                                .disabled(audioPlayer.isLoading || audioPlayer.error != nil)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if audioPlayer.isLoading {
                                        Text("Loading audio...")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    } else if let error = audioPlayer.error {
                                        Text("Error loading audio")
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                        Text(error)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    } else {
                                        Text(isPlaying ? "Playing" : "Tap to play")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        if let duration = audioPlayer.duration {
                                            Text(formatTime(duration))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        
                        // Timestamp
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Created")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text(formatDate(trace.timestamp))
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            if let trace = selectedTrace {
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
                                .foregroundColor(.secondary)
                            
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
                            .foregroundColor(.secondary)
                        
                        TextField("Enter a name...", text: objectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(isUploading)
                    }
                    
                    // Upload button
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Upload")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        // Validation messages
                        if objectName.wrappedValue.isEmpty {
                            Text("Please enter a name for your trace")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        
                        if !hasSelectedLocation {
                            Text("Tap the map to select a location")
                                .font(.caption)
                                .foregroundColor(.orange)
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
                            .background(isUploading ? Color.gray : Color.blue)
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
        if isPlaying {
            audioPlayer.pause()
        } else {
            audioPlayer.play()
        }
        isPlaying.toggle()
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
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
                
                // Trace Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(trace.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(formatDate(trace.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
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
    @Published var isLoading = false
    @Published var error: String?
    
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
    }
    
    func pause() {
        player?.pause()
    }
    
    func stop() {
        player?.stop()
        player?.currentTime = 0
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
