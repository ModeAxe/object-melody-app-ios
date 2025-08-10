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
    static let geohashPerCellLimit: Int = 12 // number of traces to fetch per geohash cell (keep small for perf)
    static let geohashMaxPrefixesPerCycle: Int = 24 // cap number of cells fetched per viewport update
}

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


// Removed unused fetchTraceSummaries

// MARK: - Geohash Utilities
// Choose fetch caps based on zoom/span to keep some hints visible at low zoom
func chooseGeohashFetchCaps(for span: MKCoordinateSpan) -> (maxPrefixes: Int, perCellLimit: Int) {
    let d = max(span.latitudeDelta, span.longitudeDelta)
    switch d {
    case 40...:
        return (maxPrefixes: 256, perCellLimit: 2)
    case 15..<40:
        return (maxPrefixes: 128, perCellLimit: 4)
    case 5..<15:
        return (maxPrefixes: 48, perCellLimit: 8)
    case 1..<5:
        return (maxPrefixes: 24, perCellLimit: 14)
    default:
        return (maxPrefixes: 12, perCellLimit: 20)
    }
}
private let geohashBase32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

func geohashEncode(latitude: Double, longitude: Double, precision: Int) -> String {
    // Inspired by common geohash implementations; sufficient for indexing/fetching
    var latInterval = (-90.0, 90.0)
    var lonInterval = (-180.0, 180.0)
    var hash = ""
    var bit = 0
    var ch = 0
    var isEven = true
    let bits = [16, 8, 4, 2, 1]
    while hash.count < precision {
        if isEven {
            let mid = (lonInterval.0 + lonInterval.1) / 2
            if longitude > mid {
                ch |= bits[bit]
                lonInterval.0 = mid
            } else {
                lonInterval.1 = mid
            }
        } else {
            let mid = (latInterval.0 + latInterval.1) / 2
            if latitude > mid {
                ch |= bits[bit]
                latInterval.0 = mid
            } else {
                latInterval.1 = mid
            }
        }
        isEven.toggle()
        if bit < 4 {
            bit += 1
        } else {
            hash.append(geohashBase32[ch])
            bit = 0
            ch = 0
        }
    }
    return hash
}

/// Center geohash + 8 neighbors (N, NE, E, SE, S, SW, W, NW)
func geohashNeighborPrefixes(around center: CLLocationCoordinate2D, precision: Int) -> [String] {
    let base = geohashEncode(latitude: center.latitude, longitude: center.longitude, precision: precision)
    // Approximate neighbors by offsetting lat/lng by one cell step
    let (cellLat, cellLonEquator) = geohashCellSizeDegrees(precision: precision)
    let lat = center.latitude
    let lon = center.longitude
    let lonStep = cellLonEquator * max(cos(lat * .pi / 180), 0.3)
    let points = [
        (lat, lon),
        (lat + cellLat, lon),
        (lat - cellLat, lon),
        (lat, lon + lonStep),
        (lat, lon - lonStep),
        (lat + cellLat, lon + lonStep),
        (lat + cellLat, lon - lonStep),
        (lat - cellLat, lon + lonStep),
        (lat - cellLat, lon - lonStep)
    ]
    var set: Set<String> = []
    for (la, lo) in points {
        set.insert(geohashEncode(latitude: la, longitude: lo, precision: precision))
    }
    // Keep base first for determinism
    var result = [base]
    result.append(contentsOf: set.filter { $0 != base })
    return result
}

/// Returns (latHeightDegrees, lonWidthDegrees at equator) for a geohash cell at a given precision
func geohashCellSizeDegrees(precision: Int) -> (Double, Double) {
    // number of bits for lon/lat
    let totalBits = 5 * precision
    let lonBits = (totalBits + 1) / 2 // ceil
    let latBits = totalBits / 2       // floor
    let lonWidth = 360.0 / pow(2.0, Double(lonBits))
    let latHeight = 180.0 / pow(2.0, Double(latBits))
    return (latHeight, lonWidth)
}

func geohashPrecision(for span: MKCoordinateSpan) -> Int {
    // Choose precision based on zoom/span – coarser when zoomed out
    let latDelta = max(span.latitudeDelta, 0.0001)
    switch latDelta {
    case 60...: return 3
    case 20..<60: return 4
    case 5..<20: return 5
    case 1..<5: return 6
    case 0.25..<1: return 7
    default: return 8
    }
}

/// Covers the bounding box with geohash prefixes at the given precision.
/// This walks the bbox in steps of the cell size so every intersecting cell is included.
func geohashBboxCover(_ region: MKCoordinateRegion, precision: Int, cap: Int = MapConstants.geohashMaxPrefixesPerCycle) -> Set<String> {
    let minLat = max(region.center.latitude - region.span.latitudeDelta / 2, -90)
    let maxLat = min(region.center.latitude + region.span.latitudeDelta / 2, 90)
    let minLng = max(region.center.longitude - region.span.longitudeDelta / 2, -180)
    let maxLng = min(region.center.longitude + region.span.longitudeDelta / 2, 180)
    let (cellLat, cellLonEquator) = geohashCellSizeDegrees(precision: precision)
    var prefixes: Set<String> = []
    var lat = minLat
    while lat <= maxLat {
        // Adjust lon step by latitude to account for convergence of meridians
        let lonStep = cellLonEquator * max(cos(lat * .pi / 180), 0.3) // clamp to avoid too small at high lat
        var lng = minLng
        while lng <= maxLng {
            let gh = geohashEncode(latitude: lat + cellLat / 2, longitude: lng + lonStep / 2, precision: precision)
            prefixes.insert(gh)
            if prefixes.count >= cap { return prefixes }
            lng += lonStep
        }
        lat += cellLat
    }
    return prefixes
}

/// Estimate approximate number of geohash cells to cover a bbox at a given precision
func geohashEstimateCellCount(_ region: MKCoordinateRegion, precision: Int) -> Int {
    let (cellLat, cellLonEquator) = geohashCellSizeDegrees(precision: precision)
    let latDelta = max(region.span.latitudeDelta, 1e-6)
    let lonAdj = max(cos(region.center.latitude * .pi / 180), 0.3)
    let lonDelta = max(region.span.longitudeDelta, 1e-6)
    let latCells = ceil(latDelta / cellLat)
    let lonCells = ceil(lonDelta / (cellLonEquator * lonAdj))
    let total = Int(latCells * lonCells)
    return max(total, 1)
}

// MARK: - Geohash-based fetching
func fetchTracesForGeohashViewport(region: MKCoordinateRegion, db: Firestore, alreadyLoadedPrefixes: Set<String>, perCellLimit: Int = MapConstants.geohashPerCellLimit, completion: @escaping (_ results: [TraceAnnotation], _ loadedPrefixes: Set<String>) -> Void) {
    var p = geohashPrecision(for: region.span)
    var prefixes = geohashBboxCover(region, precision: p, cap: MapConstants.geohashMaxPrefixesPerCycle)
    // Reduce precision if too many prefixes
    while prefixes.count > MapConstants.geohashMaxPrefixesPerCycle && p > 3 {
        p -= 1
        prefixes = geohashBboxCover(region, precision: p, cap: MapConstants.geohashMaxPrefixesPerCycle)
    }
    // Only load a capped number per cycle
    let candidates = Array(prefixes.subtracting(alreadyLoadedPrefixes)).prefix(MapConstants.geohashMaxPrefixesPerCycle)
    // Debug removed
    if candidates.isEmpty {
        // No new prefixes
        completion([], alreadyLoadedPrefixes)
        return
    }
    var merged: [TraceAnnotation] = []
    var newLoaded = alreadyLoadedPrefixes
    let group = DispatchGroup()
    let lock = NSLock()
    for prefix in candidates {
        group.enter()
        let lower = prefix
        let upper = prefix + "~" // tilde is after 'z' in ASCII to bound prefix
        let query = db.collection("traces")
            .whereField("geohash", isGreaterThanOrEqualTo: lower)
            .whereField("geohash", isLessThan: upper)
            .limit(to: perCellLimit)
        query.getDocuments { snapshot, error in
            defer { group.leave() }
            if let error = error {
                print(error)
                return
            }
            guard let documents = snapshot?.documents else {
                // No snapshot for prefix
                return
            }
            // Prefix docs count
            var local: [TraceAnnotation] = []
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
                local.append(
                    TraceAnnotation(
                        id: doc.documentID,
                        name: name,
                        coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                        audioURL: audioURL,
                        imageURL: imageURL,
                        timestamp: timestamp.dateValue()
                    )
                )
            }
            lock.lock()
            merged.append(contentsOf: local)
            newLoaded.insert(prefix)
            lock.unlock()
        }
    }
    group.notify(queue: .main) {
        completion(merged, newLoaded)
    }
}

// MARK: - Step 1: Minimal geohash viewport fetch (no caching, immediate render)
func fetchGeohashViewportSimple(region: MKCoordinateRegion, db: Firestore, perCellLimit: Int = 12, maxPrefixes: Int = 16, completion: @escaping ([TraceAnnotation]) -> Void) {
    // Choose precision from span but clamp to [5,8] per data stored
    var p = geohashPrecision(for: region.span)
    p = max(5, min(8, p))
    // Reduce precision until estimated cells fits budget, to ensure coverage
    var est = geohashEstimateCellCount(region, precision: p)
    while est > maxPrefixes && p > 3 {
        p -= 1
        est = geohashEstimateCellCount(region, precision: p)
    }
    // If too few cells, gently increase precision for a bit more resolution (optional)
    if est < max(3, maxPrefixes / 4) { p = min(p + 1, 8); est = geohashEstimateCellCount(region, precision: p) }
    let prefixesSlice = Array(geohashBboxCover(region, precision: p, cap: maxPrefixes)).prefix(maxPrefixes)
    let prefixes = Array(prefixesSlice)
    if prefixes.isEmpty {
        completion([])
        return
    }

    var mergedById: [String: TraceAnnotation] = [:]
    let group = DispatchGroup()
    let lock = NSLock()
    for prefix in prefixes {
        group.enter()
        let lower = prefix
        let upper = prefix + "~"
        let q = db.collection("traces")
            .whereField("geohash", isGreaterThanOrEqualTo: lower)
            .whereField("geohash", isLessThan: upper)
            .limit(to: perCellLimit)
        q.getDocuments { snap, err in
            defer { group.leave() }
            if let err = err {
                print(err)
                return
            }
            guard let docs = snap?.documents else { return }
            var local: [String: TraceAnnotation] = [:]
            for doc in docs {
                let data = doc.data()
                guard let location = data["location"] as? GeoPoint,
                      let audioStr = data["audioPath"] as? String,
                      let imageStr = data["imagePath"] as? String,
                      let audioURL = URL(string: audioStr),
                      let imageURL = URL(string: imageStr),
                      let name = data["name"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp else { continue }
                local[doc.documentID] = TraceAnnotation(
                    id: doc.documentID,
                    name: name,
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    audioURL: audioURL,
                    imageURL: imageURL,
                    timestamp: timestamp.dateValue()
                )
            }
            lock.lock(); defer { lock.unlock() }
            for (k, v) in local { mergedById[k] = v }
        }
    }
    group.notify(queue: .main) {
        if mergedById.isEmpty {
            // Fallback to neighbors
            let neighborPrefixes = geohashNeighborPrefixes(around: region.center, precision: max(5, min(8, p)))
            if neighborPrefixes.isEmpty { completion([]); return }
            var mergedFallback: [String: TraceAnnotation] = [:]
            let g2 = DispatchGroup()
            for prefix in neighborPrefixes.prefix(maxPrefixes) {
                g2.enter()
                let lower = prefix
                let upper = prefix + "~"
                let q = db.collection("traces")
                    .whereField("geohash", isGreaterThanOrEqualTo: lower)
                    .whereField("geohash", isLessThan: upper)
                    .limit(to: perCellLimit)
                q.getDocuments { snap, err in
                    defer { g2.leave() }
                    guard err == nil, let docs = snap?.documents else { return }
                    for doc in docs {
                        let data = doc.data()
                        guard let location = data["location"] as? GeoPoint,
                              let audioStr = data["audioPath"] as? String,
                              let imageStr = data["imagePath"] as? String,
                              let audioURL = URL(string: audioStr),
                              let imageURL = URL(string: imageStr),
                              let name = data["name"] as? String,
                              let timestamp = data["timestamp"] as? Timestamp else { continue }
                        mergedFallback[doc.documentID] = TraceAnnotation(
                            id: doc.documentID,
                            name: name,
                            coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                            audioURL: audioURL,
                            imageURL: imageURL,
                            timestamp: timestamp.dateValue()
                        )
                    }
                }
            }
            g2.notify(queue: .main) {
                let minLat = region.center.latitude - region.span.latitudeDelta / 2
                let maxLat = region.center.latitude + region.span.latitudeDelta / 2
                let minLng = region.center.longitude - region.span.longitudeDelta / 2
                let maxLng = region.center.longitude + region.span.longitudeDelta / 2
                let filtered = mergedFallback.values.filter { ann in
                    let lat = ann.coordinate.latitude
                    let lng = ann.coordinate.longitude
                    return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
                }
                .sorted(by: { $0.timestamp > $1.timestamp })
                // Fallback merged
                if filtered.isEmpty {
                    // Final probe to verify connectivity/collection
                    db.collection("traces").limit(to: 1).getDocuments { snap, err in
                        if let err = err {
                            print(err)
                            completion([]);
                            return }
                        let _ = snap?.documents.count ?? 0
                        // As a last resort at very low zoom, show recent global samples so user sees hints
                        let d = max(region.span.latitudeDelta, region.span.longitudeDelta)
                        if d >= 40 { // continent/world view
                            db.collection("traces").order(by: "timestamp", descending: true).limit(to: 60).getDocuments { snap2, err2 in
                                if let err2 = err2 {
                                    print(err2)
                                    completion([]);
                                    return }
                                guard let docs2 = snap2?.documents else { completion([]); return }
                                let pins: [TraceAnnotation] = docs2.compactMap { doc in
                                    let data = doc.data()
                                    guard let location = data["location"] as? GeoPoint,
                                          let audioStr = data["audioPath"] as? String,
                                          let imageStr = data["imagePath"] as? String,
                                          let audioURL = URL(string: audioStr),
                                          let imageURL = URL(string: imageStr),
                                          let name = data["name"] as? String,
                                          let timestamp = data["timestamp"] as? Timestamp else { return nil }
                                    return TraceAnnotation(
                                        id: doc.documentID,
                                        name: name,
                                        coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                                        audioURL: audioURL,
                                        imageURL: imageURL,
                                        timestamp: timestamp.dateValue()
                                    )
                                }
                                // Global sample count
                                completion(pins)
                            }
                        } else {
                            completion(filtered)
                        }
                    }
                } else {
                    completion(filtered)
                }
            }
            return
        }
        // Primary path
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLng = region.center.longitude - region.span.longitudeDelta / 2
        let maxLng = region.center.longitude + region.span.longitudeDelta / 2
        let filtered = mergedById.values.filter { ann in
            let lat = ann.coordinate.latitude
            let lng = ann.coordinate.longitude
            return lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
        }
        .sorted(by: { $0.timestamp > $1.timestamp })
        // Primary merged
        completion(filtered)
    }
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

func uploadTrace(audioURL: URL, imageURL: URL, location: CLLocationCoordinate2D, name: String, completion: @escaping (Bool) -> Void) {
    let storage = Storage.storage()
    let db = Firestore.firestore()
    
    let traceId = UUID().uuidString
    let audioRef = storage.reference().child("traces/audio/\(traceId).m4a")
    let imageRef = storage.reference().child("traces/images/\(traceId).png")
    
    // Upload audio
    audioRef.putFile(from: audioURL, metadata: nil) { _, error in
        guard error == nil else { print("Audio upload error: \(error!)"); completion(false); return }
        
        // Get audio URL
        audioRef.downloadURL { audioDownloadURL, error in
            guard let audioURL = audioDownloadURL else { print("Failed to get audio URL"); completion(false); return }
            
            // Upload image
            imageRef.putFile(from: imageURL, metadata: nil) { _, error in
                guard error == nil else { print("Image upload error: \(error!)"); completion(false); return }
                
                // Get image URL
                imageRef.downloadURL { imageDownloadURL, error in
                    guard let imageURL = imageDownloadURL else { print("Failed to get image URL"); completion(false); return }
                    
                    let gh = geohashEncode(latitude: location.latitude, longitude: location.longitude, precision: 8)
                    // Write Firestore document
                    let traceData: [String: Any] = [
                        "name": name,
                        "location": GeoPoint(latitude: location.latitude, longitude: location.longitude),
                        "lat": location.latitude,
                        "lng": location.longitude,
                        "geohash": gh,
                        "timestamp": Timestamp(date: Date()),
                        "audioPath": audioURL.absoluteString,
                        "imagePath": imageURL.absoluteString
                    ]
                    
                    db.collection("traces").document(traceId).setData(traceData) { error in
                        if let error = error {
                            print("Error writing document: \(error)")
                            completion(false)
                        } else {
                            print("Trace successfully uploaded!")
                            completion(true)
                        }
                    }
                }
            }
        }
    }
}
