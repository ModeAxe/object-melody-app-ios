//
//  MapViewHelpers.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/18/25.
//
import Foundation
import MapKit
import FirebaseStorage
import FirebaseFirestore
import AudioKit
import AVFoundation

// MARK: - Constants
struct MapConstants {
    static let individualTracesThreshold: Double = 5.0 // degrees - show all individual traces below this
    static let summaryThreshold: Double = 20.0 // degrees - show summaries above this
}

// MARK: - Data Structures
struct GeographicRegion {
    let name: String
    let minLat: Double
    let maxLat: Double
    let minLng: Double
    let maxLng: Double
    let centerCoordinate: CLLocationCoordinate2D
}

struct TraceSummary: Identifiable {
    let id = UUID()
    let region: String
    let count: Int
    let coordinate: CLLocationCoordinate2D
}

// MARK: - Geographic Regions
let geographicRegions = [
    GeographicRegion(name: "North America", minLat: 15.0, maxLat: 75.0, minLng: -170.0, maxLng: -50.0, centerCoordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -100.0)),
    GeographicRegion(name: "South America", minLat: -55.0, maxLat: 15.0, minLng: -85.0, maxLng: -35.0, centerCoordinate: CLLocationCoordinate2D(latitude: -15.0, longitude: -60.0)),
    GeographicRegion(name: "Europe", minLat: 35.0, maxLat: 70.0, minLng: -10.0, maxLng: 40.0, centerCoordinate: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0)),
    GeographicRegion(name: "Africa", minLat: -35.0, maxLat: 35.0, minLng: -20.0, maxLng: 50.0, centerCoordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 20.0)),
    GeographicRegion(name: "Asia", minLat: 10.0, maxLat: 75.0, minLng: 40.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 100.0)),
    GeographicRegion(name: "Australia", minLat: -45.0, maxLat: -10.0, minLng: 110.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: -25.0, longitude: 135.0)),
    GeographicRegion(name: "Antarctica", minLat: -90.0, maxLat: -60.0, minLng: -180.0, maxLng: 180.0, centerCoordinate: CLLocationCoordinate2D(latitude: -75.0, longitude: 0.0))
]

struct RuntimeError: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}

// MARK: - Location Helpers
func fetchApproximateLocation() async -> CLLocationCoordinate2D? {
    guard let url = URL(string: "http://ip-api.com/json") else { return nil }
    
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let lat = json?["lat"] as? Double,
              let lon = json?["lon"] as? Double else { return nil }
        
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    } catch {
        print("Error fetching location: \(error)")
        return nil
    }
}

// MARK: - Trace Fetching Helpers
func fetchAllTraces(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore, completion: @escaping ([TraceAnnotation]) -> Void) {
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
        guard let documents = snapshot?.documents else { 
            completion([])
            return 
        }
        
        var pins: [TraceAnnotation] = []
        
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
                id: doc.documentID,
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                audioURL: audioURL,
                imageURL: imageURL,
                timestamp: timestamp.dateValue()
            )
            
            pins.append(annotation)
        }
        
        completion(pins)
    }
}

func fetchLimitedTraces(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore, limit: Int, completion: @escaping ([TraceAnnotation]) -> Void) {
    // Use center-based query with limit
    let query = db.collection("traces")
        .limit(to: limit)
    
    query.getDocuments { snapshot, error in
        guard let documents = snapshot?.documents else { 
            completion([])
            return 
        }
        
        var pins: [TraceAnnotation] = []
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
                    id: doc.documentID,
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    audioURL: audioURL,
                    imageURL: imageURL,
                    timestamp: timestamp.dateValue()
                )
                
                pins.append(annotation)
            }
        }
        
        completion(pins)
    }
}

func fetchTraceSummaries(for center: CLLocationCoordinate2D, span: MKCoordinateSpan, db: Firestore) async -> [TraceSummary] {
    var summaries: [TraceSummary] = []
    
    for region in geographicRegions {
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
    
    return summaries
}

// MARK: - File Preparation Helpers
func prepareAudio(from originalUrl: URL) async throws -> URL {
    
    let asset = AVAsset(url: originalUrl)

    let fileName = originalUrl.deletingPathExtension().lastPathComponent.appending(".m4a")
    guard let outputURL = NSURL.fileURL(withPathComponents: [NSTemporaryDirectory(), fileName])
    else { throw RuntimeError("Coud not create output url") }

    try? FileManager.default.removeItem(at: outputURL)

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
    else { throw RuntimeError("Could not start export session") }
    
    exportSession.outputFileType = AVFileType.m4a
    exportSession.outputURL = outputURL

    await exportSession.export()

    if exportSession.status == .completed { return outputURL }
    
    else {
        print("M4A export did not complete")
        print("Error: \(exportSession.error?.localizedDescription ?? "Unknown error")")
        throw RuntimeError("Did not complete m4a export")
    }
}

func prepareImage(originalImage: UIImage) throws -> URL {
    // Resize image to max 800px dimension
    let maxDimension: CGFloat = 800
    let aspectRatio = originalImage.size.width / originalImage.size.height
    let newSize: CGSize
    if aspectRatio > 1 {
        // Landscape
        newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
    } else {
        // Portrait or square
        newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
    }
    let resizedImage = originalImage.resize(to: newSize)

    // Create a URL in the /tmp directory
    var tempFileName = UUID().uuidString
    tempFileName.append(".png")

    guard let imageURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(tempFileName) else {
        throw RuntimeError("Could not create temporary file URL")
    }

    let pngData = resizedImage.pngData();
    do {
        try pngData?.write(to: imageURL);
    } catch {
        throw RuntimeError("Could not write PNG data to file: \(error)")
    }
    
    return imageURL
}

func uploadTrace(audioURL: URL, imageURL: URL, location: CLLocationCoordinate2D, name: String) {
    let storage = Storage.storage()
    let db = Firestore.firestore()
    
    let traceId = UUID().uuidString
    let audioRef = storage.reference().child("traces/audio/\(traceId).m4a")
    let imageRef = storage.reference().child("traces/images/\(traceId).png")
    
    // Upload audio
    audioRef.putFile(from: audioURL, metadata: nil) { _, error in
        guard error == nil else { print("Audio upload error: \(error!)"); return }
        
        // Get audio URL
        audioRef.downloadURL { audioDownloadURL, error in
            guard let audioURL = audioDownloadURL else { print("Failed to get audio URL"); return }
            
            // Upload image
            imageRef.putFile(from: imageURL, metadata: nil) { _, error in
                guard error == nil else { print("Image upload error: \(error!)"); return }
                
                // Get image URL
                imageRef.downloadURL { imageDownloadURL, error in
                    guard let imageURL = imageDownloadURL else { print("Failed to get image URL"); return }
                    
                    // Write Firestore document
                    let traceData: [String: Any] = [
                        "name": name,
                        "location": GeoPoint(latitude: location.latitude, longitude: location.longitude),
                        "timestamp": Timestamp(date: Date()),
                        "audioPath": audioURL.absoluteString,
                        "imagePath": imageURL.absoluteString
                    ]
                    
                    db.collection("traces").document(traceId).setData(traceData) { error in
                        if let error = error {
                            print("Error writing document: \(error)")
                        } else {
                            print("Trace successfully uploaded!")
                        }
                    }
                }
            }
        }
    }
}
