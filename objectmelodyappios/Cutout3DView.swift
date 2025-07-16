import SwiftUI

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
    
    var body: some View {
        let pitchDeg = clamp(-pitch * 180 / .pi / 2, -cutoutRotationClamp, cutoutRotationClamp)
        let rollDeg = clamp(-roll * 180 / .pi / 2, -cutoutRotationClamp, cutoutRotationClamp)
        // Note: yaw is not used in the current UI, but can be added if desired
        let squareSize = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.7
        ZStack {
            // background
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray,
                            Color.white
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            // Outline
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black, lineWidth: 3)
            // Cutout image
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: squareSize * 0.82, height: squareSize * 0.82)
                .shadow(color: Color.black.opacity(0.3), radius: 24, x: 0, y: 12)
                .rotation3DEffect(.degrees(pitchDeg), axis: (x: 1, y: 0, z: 0))
                .rotation3DEffect(.degrees(rollDeg), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: squareSize, height: squareSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }
} 