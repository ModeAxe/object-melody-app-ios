import SwiftUI

struct SonificationMethodSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var sonificationSelector: SonificationStrategySelector
    let melodyPlayer: MelodyPlayer
    let onMethodChanged: () -> Void
    
    // Persisted appearance just for the bottom sheet
    @AppStorage("bottomSheetDarkMode") private var bottomSheetDarkMode: Bool = false
    
    // Use the same colors as the map bottom sheet
    private let colors = BottomSheetColors.self
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            // Header
            HStack {
                Text("Sonification Method")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(colors.text)
                
                Spacer()
                
                Button("Done") {
                    isPresented = false
                }
                .foregroundColor(colors.accent)
                .font(.headline)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Method list
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(SonificationMethod.allCases, id: \.self) { method in
                        MethodRow(
                            method: method,
                            isSelected: sonificationSelector.currentMethod == method,
                            onTap: {
                                sonificationSelector.setMethodAndStopAudio(method, melodyPlayer: melodyPlayer)
                                onMethodChanged() // Notify parent that method changed
                                isPresented = false
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            
            // Appearance toggle (light/dark) — minimal built-in switch
            Divider()
                .padding(.top, 4)
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.yellow)
                Toggle("", isOn: $bottomSheetDarkMode)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: colors.accent))
                    .onChange(of: bottomSheetDarkMode) { _, _ in
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    }
                Image(systemName: "moon.fill")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .padding(.bottom, 30)
        }
        .background(colors.background)
        .shadow(color: colors.shadow, radius: 10, x: 0, y: -5)
        // Limit color scheme to the sheet only, animate crossfade on change
        .environment(\.colorScheme, bottomSheetDarkMode ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: bottomSheetDarkMode)
    }
}

struct MethodRow: View {
    let method: SonificationMethod
    let isSelected: Bool
    let onTap: () -> Void
    
    private let colors = BottomSheetColors.self
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Method icon
                Image(systemName: iconForMethod(method))
                    .font(.title2)
                    .foregroundColor(isSelected ? colors.accent : colors.textSecondary)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.rawValue)
                        .font(.headline)
                        .foregroundColor(colors.text)
                    
                    Text(method.description)
                        .font(.caption)
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(colors.accent)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? colors.accentLight.opacity(0.3) : colors.secondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? colors.accent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForMethod(_ method: SonificationMethod) -> String {
        switch method {
        case .outline:
            return "pencil.and.outline"
        case .grid:
            return "grid"
        case .histogramChords:
            return "chart.bar.xaxis"
        }
    }
}
