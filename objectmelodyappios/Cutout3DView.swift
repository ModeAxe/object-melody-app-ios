import SwiftUI
import Shimmer

/// A view that displays a cutout image with 3D rotation inside a centered square with a gradient background and outline.
/// - Parameters:
///   - image: The cutout UIImage to display.
///   - pitch: The pitch value (radians) for 3D rotation.
///   - roll: The roll value (radians) for 3D rotation.
///   - yaw: The yaw value (radians) for 3D rotation.
///   - cutoutRotationClamp: The maximum absolute rotation (degrees) for each axis.
struct Cutout3DView: View {
    let image: UIImage
    let pitch: Double
    let roll: Double
    let yaw: Double
    let cutoutRotationClamp: Double
    let backgroundColor: Color
    let isTransitioning: Bool
    
    var body: some View {
        let pitchDeg = clamp(-pitch * 180 / .pi / 2, -cutoutRotationClamp, cutoutRotationClamp)
        let rollDeg = clamp(-roll * 180 / .pi / 2, -cutoutRotationClamp, cutoutRotationClamp)
        // Playing card proportions (2.5:3.5 ratio)
        let cardWidth = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.6
        let cardHeight = cardWidth * 1.4
        ZStack {
            // Card shadow (behind the card)
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .frame(width: cardWidth, height: cardHeight)
                .offset(x: 4, y: 8)
                .blur(radius: 12)
            
            // Card background (gradient with white border)
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            backgroundColor.opacity(1),
                            backgroundColor.opacity(0.8)
                        ]),
                        startPoint: isTransitioning ? .leading : .bottom,
                        endPoint: isTransitioning ? .trailing : .top
                    )
                )
                .frame(width: cardWidth, height: cardHeight)
                .animation(.easeInOut(duration: 0.4), value: backgroundColor)
                .animation(.easeInOut(duration: 0.4), value: isTransitioning)

            
            // Cutout image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: cardWidth - 32, height: cardWidth - 32)
                .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            Rectangle()
                .fill(Color.white)
                .opacity(0.4)
                .shimmering(animation: Animation.easeInOut(duration: 3).repeatForever(autoreverses: true))
        }
        .frame(width: cardWidth, height: cardHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .rotation3DEffect(.degrees(pitchDeg), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(rollDeg), axis: (x: 0, y: 1, z: 0))
        .padding()
    }
} 
