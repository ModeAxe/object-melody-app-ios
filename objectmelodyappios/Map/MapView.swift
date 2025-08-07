import SwiftUI
import MapKit
import FirebaseFirestore
import Firebase
import AVFoundation

/// A map view that can be used for both browsing existing pins and adding new pins.
struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Mode management
    @State var isAddMode: Bool
    let recordingURL: URL?
    let cutoutImage: UIImage?
    let initialLocation: CLLocationCoordinate2D?
    
    // Map state
    @State private var cameraPosition: MapCameraPosition
    @State private var pins: [TraceAnnotation] = [] // Placeholder for existing pins
    
    // Initializer to set up camera position
    init(isAddMode: Bool, recordingURL: URL?, cutoutImage: UIImage?, initialLocation: CLLocationCoordinate2D? = nil) {
        self.isAddMode = isAddMode
        self.recordingURL = recordingURL
        self.cutoutImage = cutoutImage
        self.initialLocation = initialLocation
        
        // Set initial camera position
        let center = initialLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // Default to SF if no location
        let region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        self._cameraPosition = State(initialValue: .region(region))
    }
    
    // Add mode state
    @State private var objectName: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var selectedLocation: CLLocationCoordinate2D?
    

    
    @State private var traceSummaries: [TraceSummary] = []
    
    // Bottom sheet state
    @State private var selectedTrace: TraceAnnotation?
    @State private var bottomSheetMode: BottomSheetMode = .list
    @State private var isExpanded = false
    

    
    var body: some View {
        ZStack {
            // Map
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let selectedLocation {
                        Annotation("Your Trace", coordinate: selectedLocation) {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [gold, .pink]),
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .stroke(.white, lineWidth: 1)
                                .frame(width: 30, height: 30)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                                .font(.title)
                        }
                    }
                    
                    ForEach(pins) { pin in
                        Annotation(pin.name, coordinate: pin.coordinate) {
                            Button(action: {
                                selectedTrace = pin
                                bottomSheetMode = .detail
                            }) {
                                TraceAnnotationView(traceAnnotation: pin)
                            }
                        }
                    }
                    
                    ForEach(traceSummaries) { summary in
                        Annotation("\(summary.count) traces", coordinate: summary.coordinate) {
                            SummaryAnnotationView(summary: summary)
                        }
                    }
                }
                .ignoresSafeArea()
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .onTapGesture { position in
                    if isAddMode {
                        if let coordinate = proxy.convert(position, from: .local) {
                            // Put pin on the map using coordinate
                            selectedLocation = coordinate
                        }
                    } else {
                        // Switch to list mode when tapping empty map area
                        bottomSheetMode = .list
                        selectedTrace = nil
                    }
                }
                .onMapCameraChange { context in
                    //print("Map camera changed: \(context.region)")
                    cameraPosition = .region(context.region)
                    fetchTraces(for: .region(context.region))
                }
            }

            
            // Top navigation
            VStack {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    Spacer()

                }
                .padding()
                
                Spacer()
            }
            .onAppear {
                fetchTraces(for: cameraPosition)
                
                // Listen for bottom sheet toggle notifications
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("ToggleBottomSheet"),
                    object: nil,
                    queue: .main
                ) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            }
            .navigationBarHidden(true)
            
            // Bottom Sheet - Always visible
            VStack {
                Spacer()
                
                MapBottomSheetView(
                    traces: pins,
                    selectedTrace: selectedTrace,
                    mode: isAddMode ? .add : bottomSheetMode,
                    onTraceSelected: { trace in
                        selectedTrace = trace
                        bottomSheetMode = .detail
                    },
                    onBackToList: {
                        bottomSheetMode = .list
                        selectedTrace = nil
                    },
                    onExpandSheet: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isExpanded = true
                        }
                    },
                    cutoutImage: cutoutImage,
                    objectName: $objectName,
                    isUploading: isUploading,
                    uploadProgress: uploadProgress,
                    onAddTrace: addTrace,
                    hasSelectedLocation: selectedLocation != nil,
                    isExpanded: isExpanded
                )
                .frame(height: isExpanded ? UIScreen.main.bounds.height * 0.8 : UIScreen.main.bounds.height * 0.4)

            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(.easeOut(duration: 0.3), value: bottomSheetMode)
            .animation(.easeOut(duration: 0.3), value: isExpanded)
        }
    }
    
    func fetchTraces(for mapView: MapCameraPosition) {
        var center: CLLocationCoordinate2D
        var span: MKCoordinateSpan
        
        let db = Firestore.firestore()
        
        if let region = mapView.region {
            center = region.center
            span = region.span
        } else {
            return
        }
        
        print("Getting Traces...")
        print("Span: \(span.latitudeDelta)° x \(span.longitudeDelta)°")
        
        // Determine fetch strategy based on zoom level
        if span.latitudeDelta > MapConstants.summaryThreshold {
            // Zoomed out - show regional summaries
            Task {
                let summaries = await fetchTraceSummaries(for: center, span: span, db: db)
                DispatchQueue.main.async {
                    self.pins = []
                    self.traceSummaries = summaries
                    print("Real trace summaries created: \(summaries.count) regions")
                }
            }
        } else if span.latitudeDelta > MapConstants.individualTracesThreshold {
            // Medium zoom - show limited individual traces
            fetchLimitedTraces(for: center, span: span, db: db, limit: 100) { pins in
                DispatchQueue.main.async {
                    self.pins = pins
                    self.traceSummaries = [] // Clear summaries when showing individual traces
                    print("Limited traces fetched: \(pins.count)")
                }
            }
        } else {
            // Zoomed in - show all individual traces
            fetchAllTraces(for: center, span: span, db: db) { pins in
                DispatchQueue.main.async {
                    self.pins = pins
                    self.traceSummaries = [] // Clear summaries when showing individual traces
                    print("Individual traces fetched: \(pins.count)")
                }
            }
        }
    }
    

    
    // Upload new pin
    func addTrace() {
        guard let originalAudioUrl = recordingURL, let cutoutUIImage = cutoutImage else { return }
        
        isUploading = true
        uploadProgress = 0.0
        
        Task {
            do {
                // Simulate progress for audio preparation
                await MainActor.run {
                    uploadProgress = 0.2
                }
                
                let audioURL = try await prepareAudio(from: originalAudioUrl)
                
                await MainActor.run {
                    uploadProgress = 0.4
                }
                
                let imageURL = try prepareImage(originalImage: cutoutUIImage)
                
                await MainActor.run {
                    uploadProgress = 0.6
                }
                
                // Now both are non-nil, proceed to upload
                uploadTrace(audioURL: audioURL, imageURL: imageURL, location: selectedLocation!, name: objectName)
                
                await MainActor.run {
                    uploadProgress = 1.0
                }
                
                // Upload completed successfully
                await MainActor.run {
                    isUploading = false
                    uploadProgress = 0.0
                    selectedLocation = nil
                    isAddMode = false
                    bottomSheetMode = .list
                    // Fetch updated traces to show the new pin
                    fetchTraces(for: cameraPosition)
                }
            } catch {
                print("Error preparing audio or image: \(error)")
                // Handle error
                await MainActor.run {
                    isUploading = false
                    uploadProgress = 0.0
                }
            }
        }
    }
    
    
    // Pin annotation view
    struct TraceAnnotationView: View {
        let traceAnnotation: TraceAnnotation
        
        var body: some View {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [.mint, .pink]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .stroke(.white, lineWidth: 1)
                .frame(width: 25, height: 25)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
    }
    
    // Summary annotation view
    struct SummaryAnnotationView: View {
        let summary: TraceSummary
        
        var body: some View {
            VStack(spacing: 2) {
                Image(systemName: "circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                Text("\(summary.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .cornerRadius(8)
            }
        }
    }
}
