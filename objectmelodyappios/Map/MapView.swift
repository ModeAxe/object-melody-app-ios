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
    
    // MARK: - Debounced and cached fetching helpers
    private func debouncedFetch(region: MKCoordinateRegion) {
        // Cancel any pending work
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [region] in
            // Only fetch if region meaningfully changed
            let key = cacheKey(for: region)
            if key == self.lastFetchKey { return }
            self.fetchTraces(for: .region(region))
        }
        debounceWorkItem = workItem
        // Debounce for smoother UX and fewer queries
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cacheKey(for region: MKCoordinateRegion) -> String {
        // Round to ~100m precision for center; include zoom level
        let lat = String(format: "%.3f", region.center.latitude)
        let lng = String(format: "%.3f", region.center.longitude)
        let dLat = String(format: "%.3f", region.span.latitudeDelta)
        let dLng = String(format: "%.3f", region.span.longitudeDelta)
        return "\(lat)_\(lng)_\(dLat)_\(dLng)"
    }

    // Add mode state
    @State private var objectName: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var showMissingLocationAlert: Bool = false
    @State private var showMissingNameAlert: Bool = false
    
    // Bottom sheet state
    @State private var selectedTrace: TraceAnnotation?
    @State private var bottomSheetMode: BottomSheetMode = .list
    @State private var isExpanded = false
    
    // Smart fetch control
    @State private var lastFetchKey: String? = nil
    @State private var debounceWorkItem: DispatchWorkItem? = nil
    @State private var isFetching: Bool = false
    @State private var loadedGeohashPrefixes: Set<String> = []
    @State private var pinsById: [String: TraceAnnotation] = [:]
    @StateObject private var sharedAudioPlayer = AudioPlayer()
    

    
    var body: some View {
        ZStack {
            // Map (clustered MKMapView)
            ClusteredMapView(
                region: Binding(
                    get: {
                        if let r = cameraPosition.region { return r }
                        let center = initialLocation ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
                    },
                    set: { newRegion in cameraPosition = .region(newRegion) }
                ),
                annotations: pins,
                onCameraChanged: { region in
                    cameraPosition = .region(region)
                    // Adaptive caps by zoom to keep hints at low zoom
                    let db = Firestore.firestore()
                    let caps = chooseGeohashFetchCaps(for: region.span)
                    fetchGeohashViewportSimple(region: region, db: db, perCellLimit: caps.perCellLimit, maxPrefixes: caps.maxPrefixes) { newPins in
                        // Minimal diffing to avoid jarring refresh
                        if self.pins.map({ $0.id }) != newPins.map({ $0.id }) {
                            self.pins = newPins
                        }
                    }
                },
                onAnnotationTapped: { ann in
                    // Centralize audio lifecycle: reset, then load the tapped trace
                    selectedTrace = ann
                    bottomSheetMode = .detail
                    sharedAudioPlayer.cancelLoading()
                    sharedAudioPlayer.stop()
                    sharedAudioPlayer.loadAudio(from: ann.audioURL)
                    // Expand the sheet when a trace is tapped on the map
                    withAnimation(.easeOut(duration: 0.3)) { isExpanded = true }
                },
                selectionCoordinate: selectedLocation,
                onMapTapped: { coord in
                    if isAddMode {
                        selectedLocation = coord
                    } else {
                        // No-op in browse mode
                    }
                }
            )
            .ignoresSafeArea()

            
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
                if let r = cameraPosition.region {
                    let db = Firestore.firestore()
                    let caps = chooseGeohashFetchCaps(for: r.span)
                    fetchGeohashViewportSimple(region: r, db: db, perCellLimit: caps.perCellLimit, maxPrefixes: caps.maxPrefixes) { newPins in
                        self.pins = newPins
                    }
                }
                
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

                // Listen for selection requirement to show alert
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("RequireMapSelection"),
                    object: nil,
                    queue: .main
                ) { _ in
                    showMissingLocationAlert = true
                }

                // Listen for name requirement to show alert
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("RequireNameAlert"),
                    object: nil,
                    queue: .main
                ) { _ in
                    showMissingNameAlert = true
                }
            }
            .onDisappear {
                debounceWorkItem?.cancel()
                debounceWorkItem = nil
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
                        // Centralize audio lifecycle: reset, then load the selected trace
                        selectedTrace = trace
                        bottomSheetMode = .detail
                        sharedAudioPlayer.cancelLoading()
                        sharedAudioPlayer.stop()
                        sharedAudioPlayer.loadAudio(from: trace.audioURL)
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
                    isExpanded: isExpanded,
                    audioPlayer: sharedAudioPlayer,
                )
                .frame(height: isExpanded ? UIScreen.main.bounds.height * 0.8 : UIScreen.main.bounds.height * 0.4)

            }
            .ignoresSafeArea(.container, edges: .bottom)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: bottomSheetMode)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: isExpanded)
        }
        .alert("Name Missing", isPresented: $showMissingNameAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please give your trace a name - it yearns for a sound to be called by.")
        }
        .alert("Select a location", isPresented: $showMissingLocationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tap the map to place your trace wherever you want before uploading.")
        }
    }
    
    func fetchTraces(for mapView: MapCameraPosition) {
        guard let region = mapView.region else { return }
        let db = Firestore.firestore()
        let caps = chooseGeohashFetchCaps(for: region.span)
        fetchGeohashViewportSimple(region: region, db: db, perCellLimit: caps.perCellLimit, maxPrefixes: caps.maxPrefixes) { newPins in
            if self.pins.map({ $0.id }) != newPins.map({ $0.id }) {
                self.pins = newPins
            }
        }
    }
    

    
    // Upload new pin
    func addTrace() {
        guard let originalAudioUrl = recordingURL, let cutoutUIImage = cutoutImage else { return }
        guard selectedLocation != nil else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            showMissingLocationAlert = true
            return
        }
        
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
                uploadTrace(audioURL: audioURL, imageURL: imageURL, location: selectedLocation!, name: objectName) { success in
                    Task { @MainActor in
                        uploadProgress = 1.0
                        isUploading = false
                        uploadProgress = 0.0
                        if success {
                            // Success haptic
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        selectedLocation = nil
                        isAddMode = false
                        bottomSheetMode = .list
                        // Fetch updated traces to show the new pin
                        fetchTraces(for: cameraPosition)
                    }
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
}
