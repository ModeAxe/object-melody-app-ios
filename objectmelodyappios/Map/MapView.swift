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
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
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
                }
                .ignoresSafeArea()
                .mapStyle(.imagery)
                .onTapGesture { position in
                    if(isAddMode) {
                        if let coordinate = proxy.convert(position, from: .local) {
                        // Put pin on the map using coordinate
                        selectedLocation = coordinate
                    }}
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
                        
                        // Upload button
                        Button(action: addTrace) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "cloud")
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
        let region = mapView.region
        var center: CLLocationCoordinate2D
        var span: MKCoordinateSpan
        
        if let region = mapView.region {
            center = region.center
            span = region.span
        } else {
            return
        }
        
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
        guard let originalAudioUrl = recordingURL, let cutoutUIImage = cutoutImage else { return }
        
        isUploading = true
        Task {
            do {
                let audioURL = try await prepareAudio(from: originalAudioUrl)
                let imageURL = try prepareImage(originalImage: cutoutUIImage)
                // Now both are non-nil, proceed to upload
                uploadTrace(audioURL: audioURL, imageURL: imageURL, location: selectedLocation!)
            } catch {
                print("Error preparing audio or image: \(error)")
                // Handle error
            }
        }
        
        isUploading = false
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
}
