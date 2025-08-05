//
//  ContentViewHelpers.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 8/5/25.
//

import SwiftUI
import MapKit

let gold = Color(red: 1.0, green: 0.7, blue: 0.78)

// Sound font index
func getColorForSoundFont(_ index: Int) -> [Color] {
    let colors: [[Color]] = [
        [Color(red: 0.34, green: 0.19, blue: 0.44), gold],
        [gold, .teal,],
        [.teal, .green],
        [.green, .orange],
        [.orange, .pink],
        [.pink, .cyan],
        [.cyan, .mint],
        [.mint, .indigo],
        [.indigo, .blue],
        [.blue, Color(red: 0.34, green: 0.19, blue: 0.44)]
    ]
    return colors[index % colors.count]
}

// Fetch approximate location from IP
func fetchUserLocation() async -> CLLocationCoordinate2D? {
    guard let url = URL(string: "https://ipapi.co/json/") else { return nil }
    
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let latitude = json?["latitude"] as? Double,
              let longitude = json?["longitude"] as? Double else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    } catch {
        print("Error fetching location: \(error)")
        return nil
    }
}

