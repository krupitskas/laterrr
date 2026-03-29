import CoreLocation
import Foundation
import SwiftData

@Model
final class SavedPlace {
    @Attribute(.unique) var id: UUID
    @Attribute(.spotlight) var name: String
    var shortAddress: String
    var fullAddress: String
    var category: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var confidence: Double
    var matchedText: String
    var selectionReason: String
    var analysisMode: String
    var websiteURLString: String?

    @Attribute(.externalStorage) var photoData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        shortAddress: String,
        fullAddress: String,
        category: String,
        latitude: Double,
        longitude: Double,
        createdAt: Date = .now,
        confidence: Double,
        matchedText: String,
        selectionReason: String,
        analysisMode: String,
        websiteURLString: String? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.shortAddress = shortAddress
        self.fullAddress = fullAddress
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.confidence = confidence
        self.matchedText = matchedText
        self.selectionReason = selectionReason
        self.analysisMode = analysisMode
        self.websiteURLString = websiteURLString
        self.photoData = photoData
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var websiteURL: URL? {
        guard let websiteURLString, !websiteURLString.isEmpty else {
            return nil
        }

        return URL(string: websiteURLString)
    }
}
