import SwiftUI

/// A pill-shaped view for main playback and recording controls.
struct MainPillView: View {
    let appState: AppFlowState
    let isPlaying: Bool
    let hasRecording: Bool
    let isRecording: Bool
    let recordingProgress: Double
    @Binding var showDeleteConfirm: Bool
    let onBack: () -> Void
    let onStop: () -> Void
    let onPlayPause: () -> Void
    let onRecord: () -> Void
    let onDelete: () -> Void
    let onCamera: () -> Void
    let onStopRecording: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 24) {
                // Back button (appears as needed)
                if appState != .camera {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                // Main action buttons for playback
                if appState == .playback {
                    // Stop button (left)
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Circle().fill(Color.black))
                    }
                    .disabled(hasRecording) // Disable when previewing recordings
                    .opacity(hasRecording ? 0.5 : 1.0)
                    // Play/Pause button (center)
                    Button(action: onPlayPause) {
                        Image(systemName: hasRecording ? "play.circle" : (isPlaying ? "pause.circle" : "play.circle"))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(isPlaying ? .white : .green)
                            .padding()
                            .background(Circle().fill(isPlaying ? Color.red : Color.white))
                    }
                    .disabled(hasRecording)
                    .opacity(hasRecording ? 0.5 : 1.0)
                    // Record/Trash button (right)
                    if hasRecording {
                        Button(action: { showDeleteConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                                .padding(16)
                                .background(Circle().fill(Color.red))
                        }
                        .confirmationDialog("Clear Recording? (Saved files will not be deleted)", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                            Button("Clear", role: .destructive) {
                                onDelete()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                    } else {
                        Button(action: onRecord) {
                            ZStack {
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 10)
                                    .frame(width: 50, height: 50)
                                Circle()
                                    .trim(from: 0, to: recordingProgress)
                                    .stroke(Color.red, style: StrokeStyle(lineWidth: 12, lineCap: .butt))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 64, height: 64)
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
                    Button(action: onCamera) {
                        Image(systemName: "circle")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .padding()
                            .background(Circle().fill(Color.accentColor))
                    }
                } else if appState == .recording {
                    Button(action: onStopRecording) {
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
} 
