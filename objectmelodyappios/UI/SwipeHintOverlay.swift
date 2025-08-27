import SwiftUI

public enum SwipeHintStyle: String { case arrowTrail, microPill }

public struct SwipeHintOverlay: View {
    public let style: SwipeHintStyle
    public let colors: [Color]
    public var debugAlwaysShow: Bool = false
    @Binding public var shouldHide: Bool

    public init(style: SwipeHintStyle, colors: [Color], debugAlwaysShow: Bool = false, shouldHide: Binding<Bool>) {
        self.style = style
        self.colors = colors
        self.debugAlwaysShow = debugAlwaysShow
        self._shouldHide = shouldHide
    }

    public var body: some View {
        Group {
            switch style {
            case .arrowTrail:
                ArrowTrailHint(colors: colors, shouldHide: $shouldHide)
            case .microPill:
                MicroPillHint(colors: colors, shouldHide: $shouldHide)
            }
        }
    }
}

// A tiny utility to delay showing content (with optional fade handled by caller)
public struct DelayedAppear<Content: View>: View {
    public let delay: TimeInterval
    public let content: () -> Content
    @State private var isVisible = false

    public init(delay: TimeInterval, @ViewBuilder content: @escaping () -> Content) {
        self.delay = delay
        self.content = content
    }

    public var body: some View {
        Group {
            if isVisible { content() }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isVisible = true
                }
            }
        }
    }
}

// MARK: - Variants
struct ArrowTrailHint: View {
    let colors: [Color]
    @Binding var shouldHide: Bool
    @State private var animateUp = false
    @State private var animateDown = false
    @State private var show = true
    @AppStorage("debugAlwaysShowSwipeHint") private var debugAlwaysShowSwipeHint: Bool = true
    @State private var internalTimer: Timer?

    var body: some View {
        if show {
            ZStack {
                VStack {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.first?.opacity(0.9) ?? .white.opacity(0.9))
                        .opacity(animateUp ? 0 : 1)
                        .offset(y: animateUp ? -18 : 0)
                    Spacer()
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.last?.opacity(0.9) ?? .white.opacity(0.9))
                        .opacity(animateDown ? 0 : 1)
                        .offset(y: animateDown ? 18 : 0)
                }
                .padding(.vertical, 24)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animateUp.toggle()
                }
                withAnimation(.easeInOut(duration: 0.8).delay(0.4).repeatForever(autoreverses: true)) {
                    animateDown.toggle()
                }
                if !debugAlwaysShowSwipeHint {
                    internalTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                        withAnimation(.easeInOut(duration: 0.5)) { show = false }
                    }
                }
            }
            .onChange(of: shouldHide) { _, newValue in
                if newValue {
                    internalTimer?.invalidate()
                    internalTimer = nil
                    withAnimation(.easeInOut(duration: 0.25)) { show = false }
                }
            }
        }
    }
}

struct MicroPillHint: View {
    let colors: [Color]
    @Binding var shouldHide: Bool
    @State private var show = true
    @State private var internalTimer: Timer?

    var body: some View {
        if show {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                Text("Swipe Up/Down to change voice")
                    .font(.footnote)
                Image(systemName: "chevron.down")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .foregroundColor(.primary.opacity(0.9))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke((colors.first ?? .white).opacity(0.5), lineWidth: 1)
            )
            .transition(.opacity)
            .onAppear {
                internalTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
                    withAnimation(.easeInOut(duration: 0.5)) { show = false }
                }
            }
            .onChange(of: shouldHide) { _, newValue in
                if newValue {
                    internalTimer?.invalidate()
                    internalTimer = nil
                    withAnimation(.easeInOut(duration: 0.25)) { show = false }
                }
            }
        }
    }
}


