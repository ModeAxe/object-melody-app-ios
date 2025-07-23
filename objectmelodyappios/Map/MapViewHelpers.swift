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

//func prepareAudio(from originalUrl: URL) -> URL {
//    
//    let newUrl = FileManager.default.temporaryDirectory
//    let options = FormatConverter.Options()
//    //options.format = "m4a"
//    originalUrl.lastPathComponent
//    let converter = FormatConverter(inputURL: originalUrl, outputURL: newUrl)
//    
//}

//func prepareImage(originalImage: UIImage) -> URL {
//    
//}

func uploadTrace(audioURL: URL, imageURL: URL, location: CLLocationCoordinate2D) {
    let storage = Storage.storage()
    let db = Firestore.firestore()
    
    let traceId = UUID().uuidString
    let audioRef = storage.reference().child("traces/audio/\(traceId).m4a")
    let imageRef = storage.reference().child("traces/images/\(traceId).jpg")
    
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
