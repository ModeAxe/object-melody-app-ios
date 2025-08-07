//
//  OnboardingWelcomeSheetView.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 8/6/25.
//

import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let description: String
    let icon: String
    let color: Color
}

struct OnboardingWelcomeSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0
    
    let onboardingPages = [
        OnboardingPage(
            title: "Welcome to Traces",
            subtitle: "traces traces traces",
            description: "A tool the helps you listen to the little melody in everything around you.",
            icon: "music.note",
            color: .blue
        ),
        OnboardingPage(
            title: "Capture Objects",
            subtitle: "Point and shoot",
            description: "Take a photo of any object. We detect it and segment and create a unique musical pattern from its shape.",
            icon: "camera.fill",
            color: .green
        ),
        OnboardingPage(
            title: "Motion Controls",
            subtitle: "Your phone as an instrument",
            description: "Tilt your phone to control the sound:\n• Pitch: Control reverb mix\n• Roll: Adjust playback speed\n• Yaw: Modulate delay effects",
            icon: "iphone.radiowaves.left.and.right",
            color: .purple
        ),
        OnboardingPage(
            title: "Playback Controls",
            subtitle: "Explore texture / melody",
            description: "• Play/Pause: Play melody sequence / hold current note (you can use this to stack notes / make drones)\n• Stop: End current playback\n• Record: Capture your performance\n• Swipe up/down: Change instrument sound",
            icon: "play.circle.fill",
            color: .orange
        ),
        OnboardingPage(
            title: "Preview & Share",
            subtitle: "Listen and share your creation",
            description: "• Preview your recording before sharing\n• Save locally to your device\n• Share with friends via messages, social media etc etc\n• Add to the global map for others to discover",
            icon: "square.and.arrow.up",
            color: .red
        ),
        OnboardingPage(
            title: "Explore the Map",
            subtitle: "Discover other melodies",
            description: "Browse a world of traces created by others. Tap any pin to listen to their unique melodies and see the objects they came from.",
            icon: "map.fill",
            color: .mint
        ),
        OnboardingPage(
            title: "That's all we have to say",
            subtitle: "Listen, Listen, Listen",
            description: "Start capturing the hidden melodies in the world around you",
            icon: "sparkles",
            color: .blue
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    onboardingPages[currentPage].color.opacity(0.1),
                    Color(.systemBackground)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Page content - simplified inline view
                TabView(selection: $currentPage) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        let page = onboardingPages[index]
                        
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // Icon
                            ZStack {
                                Circle()
                                    .fill(page.color.opacity(0.2))
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: page.icon)
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundColor(page.color)
                            }
                            
                            // Content
                            VStack(spacing: 20) {
                                Text(page.title)
                                    .font(.system(size: 32, weight: .bold, design: .default))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text(page.subtitle)
                                    .font(.system(size: 20, weight: .semibold, design: .default))
                                    .foregroundColor(page.color)
                                    .multilineTextAlignment(.center)
                                
                                Text(page.description)
                                    .font(.system(size: 16, weight: .regular, design: .default))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .padding(.horizontal, 40)
                            }
                            
                            Spacer()
                            
                            // Action button only on last page
                            if index == onboardingPages.count - 1 {
                                Button(action: {
                                    dismiss()
                                }) {
                                    Text("Get Started")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(page.color)
                                        .cornerRadius(12)
                                }
                                .padding(.horizontal, 40)
                                .padding(.bottom, 20)
                            }
                        }
                        .padding(.horizontal, 20)
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<onboardingPages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? onboardingPages[currentPage].color : Color(.systemGray4))
                            .frame(width: 8, height: 8)
                            .animation(.linear(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 30)
                
                // Navigation pill
                HStack(spacing: 20) {
                    // Previous button
                    Button(action: {
                        if currentPage > 0 {
                            withAnimation(.linear(duration: 0.2)) {
                                currentPage -= 1
                            }
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(currentPage > 0 ? .primary : .secondary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    .disabled(currentPage == 0)
                    
                    Spacer()
                    
                    // Next/Dismiss button
                    Button(action: {
                        if currentPage < onboardingPages.count - 1 {
                            withAnimation(.linear(duration: 0.2)) {
                                currentPage += 1
                            }
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: currentPage < onboardingPages.count - 1 ? "chevron.right" : "checkmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(onboardingPages[currentPage].color))
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    let isLastPage: Bool
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: page.icon)
                    .font(.system(size: 50, weight: .medium))
                    .foregroundColor(page.color)
            }
            
            // Content
            VStack(spacing: 20) {
                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundColor(page.color)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Action button
            if isLastPage {
                Button(action: onComplete) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(page.color)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 20)
    }
}

#Preview {
    OnboardingWelcomeSheetView()
}
