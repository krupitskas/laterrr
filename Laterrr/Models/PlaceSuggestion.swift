import CoreLocation
import Foundation

struct VenueCandidate: Identifiable {
    let id: String
    let name: String
    let shortAddress: String
    let fullAddress: String
    let category: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let websiteURL: URL?
    let phoneNumber: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlaceSuggestion: Identifiable {
    let candidate: VenueCandidate
    var score: Double
    var rationale: String
    var matchedTokens: [String]

    var id: String { candidate.id }
    var name: String { candidate.name }
    var shortAddress: String { candidate.shortAddress }
    var fullAddress: String { candidate.fullAddress }
    var category: String { candidate.category }
    var latitude: Double { candidate.latitude }
    var longitude: Double { candidate.longitude }
    var distanceMeters: Double { candidate.distanceMeters }
    var websiteURL: URL? { candidate.websiteURL }
    var phoneNumber: String? { candidate.phoneNumber }
    var coordinate: CLLocationCoordinate2D { candidate.coordinate }
}

struct CaptureAnalysisPayload {
    let extractedText: [String]
    let suggestions: [PlaceSuggestion]
    let analysisMethod: String
    let narrative: String
}
