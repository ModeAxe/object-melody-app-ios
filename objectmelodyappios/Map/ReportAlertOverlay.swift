//
//  ReportAlertOverlay.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/18/25.
//

import SwiftUI

struct ReportAlertOverlay: View {
    let trace: TraceAnnotation
    @Binding var isPresented: Bool
    @StateObject private var reportService = ReportService()
    
    @State private var selectedCategory: ReportCategory = .inappropriate
    @State private var description: String = ""
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isSubmitting {
                        isPresented = false
                    }
                }
            
            // Alert content
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    
                    Text("Report Trace")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Help us keep the community safe")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Category Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Menu {
                        ForEach(ReportCategory.allCases, id: \.self) { category in
                            Button(action: {
                                selectedCategory = category
                            }) {
                                HStack {
                                    Text(category.rawValue)
                                    if selectedCategory == category {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(selectedCategory.rawValue)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Provide additional details...", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        if !isSubmitting {
                            isPresented = false
                        }
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .cornerRadius(10)
                    .disabled(isSubmitting)
                    
                    Button(action: submitReport) {
                        HStack(spacing: 6) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                            }
                            Text(isSubmitting ? "Submitting..." : "Submit")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isSubmitting ? Color.gray : Color.red)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(duration: 0.3, bounce: 0.2), value: isPresented)
        .alert("Report Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            Text("Thank you for your report. We'll review it and take appropriate action.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        
        Task {
            do {
                try await reportService.submitReport(
                    traceId: trace.id,
                    traceName: trace.name,
                    latitude: trace.coordinate.latitude,
                    longitude: trace.coordinate.longitude,
                    geohash: trace.geohash,
                    category: selectedCategory,
                    description: description.isEmpty ? "No description provided" : description
                )
                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Failed to submit report: \(error.localizedDescription)"
                    showErrorAlert = true
                }
            }
        }
    }
}
