//
//  TraceAnnotation.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/18/25.
//

import MapKit

class TraceAnnotation: NSObject, MKAnnotation, Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let audioURL: URL
    let imageURL: URL
    let timestamp: Date
    
    var title: String? {
        name
    }
    
    init(name:String, coordinate: CLLocationCoordinate2D, audioURL: URL, imageURL: URL, timestamp: Date) {
        self.name = name
        self.coordinate = coordinate
        self.audioURL = audioURL
        self.imageURL = imageURL
        self.timestamp = timestamp
        
    }
}

