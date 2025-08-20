//
//  ReportModel.swift
//  objectmelodyappios
//
//  Created by Elijah Temwani Zulu on 7/18/25.
//

import Foundation
import FirebaseFirestore

enum ReportCategory: String, CaseIterable {
    case inappropriate = "Inappropriate Content"
    case spam = "Spam/Fake Content"
    case technical = "Technical Issue"
    case other = "Other"
}

class ReportService: ObservableObject {
    private let db = Firestore.firestore()
    
    func submitReport(traceId: String, traceName: String, latitude: Double, longitude: Double, geohash: String, category: ReportCategory, description: String) async throws {
        let reportData: [String: Any] = [
            "traceId": traceId,
            "traceName": traceName,
            "latitude": latitude,
            "longitude": longitude,
            "geohash": geohash,
            "category": category.rawValue,
            "description": description,
            "timestamp": Timestamp(date: Date()),
        ]
        
        try await db.collection("reports").addDocument(data: reportData)
    }
}
