import SwiftUI

/// A pill-shaped view for preview controls (share, preview play, network).
struct PreviewPillView: View {
    let hasRecording: Bool
    let recordingURL: URL?
    let isPreviewing: Bool
    let previewProgress: Double
    let onShare: () -> Void
    let onPreviewPlay: () -> Void
    let onNetwork: () -> Void
    
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 24) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.green))
                }
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 10)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: previewProgress)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                        .animation(.linear(duration: 0.1), value: previewProgress)
                    Button(action: onPreviewPlay) {
                        Image(systemName: isPreviewing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(Circle().fill(Color.white))
                    }
                    .frame(width: 48, height: 48)
                }
                Button(action: onNetwork) {
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
} 
