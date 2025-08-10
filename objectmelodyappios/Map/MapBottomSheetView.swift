import SwiftUI
import AudioKit
import AVFoundation
import UIKit

// MARK: - Color Scheme Constants
struct BottomSheetColors {
    static let background = Color("ListViewBackgroundNoDark")
    static let secondaryBackground = Color("ListViewSecondaryBackgroundNoDark")
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
    
    // Shared audio player provided by parent to avoid per-view races
    let audioPlayer: AudioPlayer

    // Deterministic gradient palettes per selected trace
    private let gradientPalettes: [[Color]] = [
        [Color(red: 0.34, green: 0.19, blue: 0.44), gold],
        [gold, .teal,],
        [.teal, .green],
        [.green, .orange],
        [.orange, .pink],
        [.pink, .cyan],
        [.cyan, .mint],
        [.mint, .indigo],
        [.indigo, .blue],
        [.blue, Color(red: 0.34, green: 0.19, blue: 0.44)]
    ]

    private var currentDetailColors: [Color] {
        guard let id = selectedTrace?.id else { return [.mint, .pink] }
        let idx = abs(id.hashValue) % gradientPalettes.count
        return gradientPalettes[idx]
    }
    
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
        // When the selected trace changes while staying on detail, stop previous and load new
        // Selection lifecycle handled in parent to avoid duplicate loads
        // If user leaves detail mode, stop audio
        .onChange(of: mode) { oldMode, newMode in
            if newMode != .detail {
                audioPlayer.stop()
            }
        }
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
                LazyVStack(spacing: 6) {
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
                        .foregroundColor(BottomSheetColors.text) //should change
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
                                            currentDetailColors[1],
                                            currentDetailColors[0]
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
                            RoundedRectangle(cornerRadius: cardCornerRadius)
                                .fill(Color.white)
                                .stroke(Color.white, lineWidth: 2)
                                .opacity(0.4)
                                .shimmering(animation: Animation.easeInOut(duration: 3).repeatForever(autoreverses: true))
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
        // Loading and stopping are centralized in MapView to avoid duplicate/racy loads
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
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: cardCornerRadius)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                currentDetailColors[1],
                                                currentDetailColors[0]
                                            ]),
                                            startPoint: .bottom,
                                            endPoint: .top
                                        )
                                    )
                                Image(uiImage: cutout)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 200)
                                    .cornerRadius(12)
                                RoundedRectangle(cornerRadius: cardCornerRadius)
                                    .fill(Color.white)
                                    .stroke(Color.white, lineWidth: 2)
                                    .opacity(0.4)
                                    .shimmering(animation: Animation.easeInOut(duration: 3).repeatForever(autoreverses: true))
                            }
                            .frame(maxHeight: 200)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        }
                    }
                    
                    // Name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name your trace")
                            .font(.headline)
                            .foregroundColor(BottomSheetColors.textSecondary)
                        
                        TextField("Namey McNameface", text: objectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .disabled(isUploading)
                            .background(BottomSheetColors.secondaryBackground)
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
                                        .foregroundColor(.black)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "cloud")
                                    Text("Share with the world")
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
        let impact = UIImpactFeedbackGenerator(style: .soft)
        if audioPlayer.isPlaying {
            impact.impactOccurred(intensity: 0.6)
            audioPlayer.pause()
        } else {
            impact.impactOccurred(intensity: 0.9)
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
            ZStack{
                HStack(spacing: 12) {
                    // Trace Image
                    AsyncImage(url: trace.imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: Color.white.opacity(1), radius: 8, x: 0, y: 0)
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
                        
    //                    Text(formatDate(trace.timestamp))
    //                        .font(.caption)
    //                        .foregroundColor(BottomSheetColors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(BottomSheetColors.textSecondary)
                        .font(.caption)
                }
                .padding()
                .background(BottomSheetColors.secondaryBackground)
                .cornerRadius(12)
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white, lineWidth: 1)
            }
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
    private var dataTask: URLSessionDataTask?
    private var loadToken = UUID()
    @Published var loadedURL: URL?
    private var pendingAutoPlay: Bool = false
    @Published var duration: TimeInterval?
    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var isLoading = false
    @Published var error: String?
    private var progressTimer: Timer?
    
    func loadAudio(from url: URL, autoPlay: Bool = false) {
        print("🎵 Loading audio from URL: \(url)")
        // Cancel any in-flight load and reset
        cancelLoading()
        stop()
        error = nil
        isLoading = true
        let token = UUID()
        loadToken = token
        pendingAutoPlay = autoPlay
        error = nil
        
        // Download the audio file first
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, self.loadToken == token else { return }
                self.isLoading = false
                
                if let error = error as NSError?, error.code == NSURLErrorCancelled {
                    return
                }
                if let error = error {
                    print("🎵 Network error loading audio: \(error)")
                    self.error = "Network error: \(error.localizedDescription)"
                    return
                }
                guard let data = data else {
                    print("🎵 No data received from URL")
                    self.error = "No audio data received"
                    return
                }
                print("🎵 Received \(data.count) bytes of audio data")
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_audio_\(UUID().uuidString).m4a")
                do {
                    try data.write(to: tempURL)
                    print("🎵 Saved audio to temp file: \(tempURL)")
                    self.player = try AVAudioPlayer(contentsOf: tempURL)
                    self.player?.prepareToPlay()
                    self.duration = self.player?.duration
                    self.loadedURL = url
                    print("🎵 Audio player created successfully, duration: \(self.duration ?? 0)")
                    if self.pendingAutoPlay {
                        self.pendingAutoPlay = false
                        self.play()
                    }
                } catch {
                    print("🎵 Error creating audio player: \(error)")
                    self.error = "Audio format error: \(error.localizedDescription)"
                }
            }
        }
        dataTask = task
        task.resume()
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
        player = nil
        loadedURL = nil
    }

    func cancelLoading() {
        dataTask?.cancel()
        dataTask = nil
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
