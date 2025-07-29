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

struct RuntimeError: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}

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
