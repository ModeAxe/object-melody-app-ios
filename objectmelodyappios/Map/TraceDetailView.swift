//
//  TraceDetailView.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/18/25.
//
import SwiftUI
import AVFoundation

// Pin detail view
struct TraceDetailView: View {
    let pin: TraceAnnotation
    @Environment(\.dismiss) private var dismiss
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?
    
    var body: some View {
        VStack(spacing: 20) {
            Text(pin.name)
                .font(.title2)
                .fontWeight(.bold)
            
            // TODO: Load and display cutout image from pin.imageURL
            
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Object Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
    }
    
    func togglePlayback() {
        // TODO: Implement audio playback using pin.audioURL
        isPlaying.toggle()
    }
}
