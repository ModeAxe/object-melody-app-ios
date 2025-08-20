//
//  ContentViewHelpers.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 8/5/25.
//

import SwiftUI
import MapKit

let notgold = Color(red: 1.0, green: 0.7, blue: 0.78)
let gold = Color(red: 1.0, green: 0.7, blue: 0.078)
let peach = Color(red: 0.95, green: 0.57, blue: 0.53)
let fall = Color(red: 0.015 , green: 0.396, blue: 0.51)
let teal = Color(red: 41/255, green: 161/255, blue: 156/255)
let lightblue = Color(red: 213/255, green: 238/255, blue: 255/255)
// Sound font index
func getColorForSoundFont(_ index: Int) -> [Color] {
    let colors: [[Color]] = [
        [Color(red: 0.34, green: 0.19, blue: 0.44), notgold],
        [notgold, .teal,],
        [.teal, .green],
        [.green, .orange],
        [.orange, .pink],
        [.pink, .cyan],
        [.cyan, .mint],
        [.mint, lightblue],
        [lightblue, teal],
        [teal, gold],
        [gold, peach],
        [peach, .indigo],
        [.indigo, fall],
        [fall, .blue],
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

