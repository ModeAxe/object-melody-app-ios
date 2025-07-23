import SwiftUI
import MapKit
import FirebaseFirestore
import Firebase
import AVFoundation

/// A map view that can be used for both browsing existing pins and adding new pins.
struct MapView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Mode management
    let isAddMode: Bool // true if coming from "network" button, false if from browse
    let recordingURL: URL?
    let cutoutImage: UIImage?
    
    // Map state
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var pins: [TraceAnnotation] = [] // Placeholder for existing pins
    
    // Add mode state
    @State private var objectName: String = ""
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var selectedLocation: CLLocationCoordinate2D?
    
    var body: some View {
        ZStack {
            // Map
            Map(coordinateRegion: $region, annotationItems: pins) { pin in
                MapAnnotation(coordinate: pin.coordinate) {
                    TraceAnnotationView(traceAnnotation: pin)
                }
            }
            .ignoresSafeArea()
            
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
                        TextField("Name your object...", text: $objectName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        
                        // Upload button
                        Button(action: addTrace) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "cloud.upload")
                                }
                                Text(isUploading ? "Uploading..." : "Add to Map")
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
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
                    
                    Spacer()
                    
                    if isAddMode {
                        Text("Add Your Recording")
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
        }
        .onAppear {
            loadExistingPins()
        }
    }
    
    // Load existing pins from backend
    func loadExistingPins() {
        // TODO: Fetch pins from backend
        // pins = await fetchPinsFromBackend()
    }
    
    func fetchTraces(for mapView: MKMapView) {
        let region = mapView.region
        let center = region.center
        let span = region.span

        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLng = center.longitude - span.longitudeDelta / 2
        let maxLng = center.longitude + span.longitudeDelta / 2

//        let query = db.collection("traces")
//            .whereField("lat", isGreaterThan: minLat)
//            .whereField("lat", isLessThan: maxLat)

//        query.getDocuments { snapshot, error in
//            guard let documents = snapshot?.documents else { return }
//
//            DispatchQueue.main.async {
//                mapView.removeAnnotations(mapView.annotations)
//
//                for doc in documents {
//                    let data = doc.data()
//                    guard let lat = data["lat"] as? CLLocationDegrees,
//                          let lng = data["lng"] as? CLLocationDegrees,
//                          let audioStr = data["audioUrl"] as? String,
//                          let imageStr = data["imageUrl"] as? String,
//                          let audioURL = URL(string: audioStr),
//                          let imageURL = URL(string: imageStr),
//                          let name = data["name"] as? String,
//                          let timestamp = data["timestamp"] as? Date,
//                          lng >= minLng, lng <= maxLng
//                    else { continue }
//
//                    let annotation = TraceAnnotation(
//                        name: name,
//                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
//                        audioURL: audioURL,
//                        imageURL: imageURL,
//                        timestamp: timestamp
//                        
//                    )
//
//                    mapView.addAnnotation(annotation)
//                }
//            }
//        }
    }
    
    // Upload new pin
    func addTrace() {
        guard let url = recordingURL, let cutout = cutoutImage else { return }
        
        isUploading = true
        
        //let recordingToUpload = prepareRecording()
        //let imageToUpload = prepareImage()
        
        //uploadTrace(audioURL: recordingURL, imageURL: cutoutImage., location: )
        
        // Placeholder: simulate upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isUploading = false
            // TODO: Switch to browse mode or refresh pins
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
