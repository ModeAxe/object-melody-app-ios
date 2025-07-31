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
    
    // Zoom thresholds for different fetch strategies
    private let individualTracesThreshold: Double = 5.0 // degrees - show all individual traces below this
    private let summaryThreshold: Double = 20.0 // degrees - show summaries above this
    
    // Predefined geographic regions for all continents
    struct GeographicRegion {
        let name: String
        let minLat: Double
        let maxLat: Double
        let minLng: Double
        let maxLng: Double
        let centerCoordinate: CLLocationCoordinate2D
    }
    
    private let regions = [
        GeographicRegion(name: "North America", minLat: 15.0, maxLat: 75.0, minLng: -170.0, maxLng: -50.0, centerCoordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -100.0)),
        GeographicRegion(name: "South America", minLat: -55.0, maxLat: 15.0, minLng: -85.0, maxLng: -35.0, centerCoordinate: CLLocationCoordinate2D(latitude: -15.0, longitude: -60.0)),
        GeographicRegion(name: "Europe", minLat: 35.0, maxLat: 70.0, minLng: -10.0, maxLng: 40.0, centerCoordinate: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)),
        GeographicRegion(name: "Africa", minLat: -35.0, maxLat: 35.0, minLng: -20.0, maxLng: 50.0, centerCoordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 20.0)),
        GeographicRegion(name: "Asia", minLat: 10.0, maxLat: 75.0, minLng: 40.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 100.0)),
        GeographicRegion(name: "Australia", minLat: -45.0, maxLat: -10.0, minLng: 110.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: -25.0, longitude: 135.0)),
        GeographicRegion(name: "Antarctica", minLat: -90.0, maxLat: -60.0, minLng: -180.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: -75.0, longitude: 0.0))
    ]
    
    // Summary data structure
    struct TraceSummary: Identifiable {
        let id = UUID()
        let region: String
        let count: Int
        let coordinate: CLLocationCoordinate2D
    }
    
    @State private var traceSummaries: [TraceSummary] = []
    

    
    var body: some View {
        ZStack {
            // Map
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let selectedLocation {
                        Annotation("Your Pin", coordinate: selectedLocation) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    ForEach(pins) { pin in
                        Annotation(pin.name, coordinate: pin.coordinate) {
                            TraceAnnotationView(traceAnnotation: pin)
                        }
                    }
                    
                    ForEach(traceSummaries) { summary in
                        Annotation("\(summary.count) traces", coordinate: summary.coordinate) {
                            SummaryAnnotationView(summary: summary)
                        }
                    }
                }
                .ignoresSafeArea()
                .mapStyle(.hybrid)
                .onTapGesture { position in
                    if(isAddMode) {
                        if let coordinate = proxy.convert(position, from: .local) {
                        // Put pin on the map using coordinate
                        selectedLocation = coordinate
                    }}
                }
                .onMapCameraChange { context in
                    //print("Map camera changed: \(context.region)")
                    cameraPosition = .region(context.region)
                    fetchTraces(for: .region(context.region))
                }
            }
            // Add mode overlay
            if isAddMode {
                VStack {
                    Spacer()
                    
                    // Add pin UI
                    VStack(spacing: 16) {
                        // Preview cutout
                        if let cutout = cutoutImage {
                            Image(uiImage: cutout)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        // Name input
                        TextField("Name your trace...", text: $objectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                            .disabled(isUploading)
                        
                        // Upload button
                        Button(action: addTrace) {
                            HStack {
                                if isUploading {
                                    ProgressView(value: uploadProgress)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                    Text("\(Int(uploadProgress * 100))%")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                } else {
                                    Image(systemName: "cloud")
                                    Text("Add to Map")
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(isUploading ? Color.gray : Color.blue)
                            .cornerRadius(10)
                        }
                        .disabled(objectName.isEmpty || isUploading)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                    .padding()
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
                    
                    if isAddMode {
                        Text("Add Your Trace")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    } else {
                        Text("Community Traces")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
            .onAppear {
                fetchTraces(for: cameraPosition)
            }
            .navigationBarHidden(true)
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
        if span.latitudeDelta > summaryThreshold {
            // Zoomed out - show regional summaries
            Task {
                await fetchTraceSummaries(for: center, span: span, db: db)
            }
        } else if span.latitudeDelta > individualTracesThreshold {
            // Medium zoom - show limited individual traces
            fetchLimitedTraces(for: center, span: span, db: db, limit: 100)
        } else {
            // Zoomed in - show all individual traces
            fetchAllTraces(for: center, span: span, db: db)
        }
    }
    
    private func fetchAllTraces(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore) {
        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLng = center.longitude - span.longitudeDelta / 2
        let maxLng = center.longitude + span.longitudeDelta / 2
        
        // Clamp values to prevent GeoPoint errors
        let clampedMinLat = min(max(minLat, -90), 90)
        let clampedMaxLat = min(max(maxLat, -90), 90)
        let clampedMinLng = min(max(minLng, -180), 180)
        let clampedMaxLng = min(max(maxLng, -180), 180)
        
        let query = db.collection("traces")
            .whereField("location", isGreaterThan: GeoPoint(latitude: clampedMinLat, longitude: clampedMinLng))
            .whereField("location", isLessThan: GeoPoint(latitude: clampedMaxLat, longitude: clampedMaxLng))
        
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            DispatchQueue.main.async {
                self.pins = []
                self.traceSummaries = [] // Clear summaries when showing individual traces
                
                for doc in documents {
                    let data = doc.data()
                    guard let location = data["location"] as? GeoPoint,
                          let audioStr = data["audioPath"] as? String,
                          let imageStr = data["imagePath"] as? String,
                          let audioURL = URL(string: audioStr),
                          let imageURL = URL(string: imageStr),
                          let name = data["name"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp
                    else { continue }
                    
                    let annotation = TraceAnnotation(
                        name: name,
                        coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                        audioURL: audioURL,
                        imageURL: imageURL,
                        timestamp: timestamp.dateValue()
                    )
                    
                    self.pins.append(annotation)
                }
                print("Individual traces fetched: \(self.pins.count)")
            }
        }
    }
    
    private func fetchLimitedTraces(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore, limit: Int) {
        // Use center-based query with limit
        let query = db.collection("traces")
            .limit(to: limit)
        
        query.getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            DispatchQueue.main.async {
                self.pins = []
                self.traceSummaries = [] // Clear summaries when showing individual traces
                
                let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let maxDistance: Double = 1000 // kilometers
                
                for doc in documents {
                    let data = doc.data()
                    guard let location = data["location"] as? GeoPoint,
                          let audioStr = data["audioPath"] as? String,
                          let imageStr = data["imagePath"] as? String,
                          let audioURL = URL(string: audioStr),
                          let imageURL = URL(string: imageStr),
                          let name = data["name"] as? String,
                          let timestamp = data["timestamp"] as? Timestamp
                    else { continue }
                    
                    // Calculate distance from center
                    let traceLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    let distance = centerLocation.distance(from: traceLocation) / 1000 // Convert to km
                    
                    if distance <= maxDistance {
                        let annotation = TraceAnnotation(
                            name: name,
                            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            audioURL: audioURL,
                            imageURL: imageURL,
                            timestamp: timestamp.dateValue()
                        )
                        
                        self.pins.append(annotation)
                    }
                }
                print("Limited traces fetched: \(self.pins.count)")
            }
        }
    }
    
    private func fetchTraceSummaries(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore) async {
        var summaries: [TraceSummary] = []
        
        for region in regions {
            // Use separate lat/lng fields instead of GeoPoint range queries
            let query = db.collection("traces")
                .whereField("lat", isGreaterThanOrEqualTo: region.minLat)
                .whereField("lat", isLessThanOrEqualTo: region.maxLat)
                .whereField("lng", isGreaterThanOrEqualTo: region.minLng)
                .whereField("lng", isLessThanOrEqualTo: region.maxLng)
            
            print("Querying \(region.name): lat \(region.minLat) to \(region.maxLat), lng \(region.minLng) to \(region.maxLng)")
            
            let countQuery = query.count
            do {
                let snapshot = try await countQuery.getAggregation(source: .server)
                let count = snapshot.count as? Int ?? 0
                
                print("Count for \(region.name): \(count)")
                
                if count > 0 {
                    let summary = TraceSummary(
                        region: region.name,
                        count: count,
                        coordinate: region.centerCoordinate
                    )
                    summaries.append(summary)
                }
                
            } catch {
                print("Error querying \(region.name): \(error)")
            }
        }
        
        DispatchQueue.main.async {
            self.pins = []
            self.traceSummaries = summaries
            print("Real trace summaries created: \(summaries.count) regions")
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
        @State private var showingDetail = false
        
        var body: some View {
            Button(action: { showingDetail.toggle() }) {
                Image(systemName: "mappin.circle.fill")
                    .font(.title)
                    .foregroundColor(.red)
            }
            .sheet(isPresented: $showingDetail) {
                TraceDetailView(pin: traceAnnotation)
            }
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
