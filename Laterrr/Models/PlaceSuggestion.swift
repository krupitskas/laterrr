import CoreLocation
import Foundation

enum LookAroundAvailability: String, Sendable {
    case available
    case unavailable
    case disabled

    var title: String {
        switch self {
        case .available:
            return "Available"
        case .unavailable:
            return "Not available"
        case .disabled:
            return "Disabled"
        }
    }
}

struct LookAroundPreview: Sendable {
    let availability: LookAroundAvailability
    let snapshotData: Data?
    let verificationScore: Double?
    let matchedTokens: [String]
    let summary: String

    static let disabled = LookAroundPreview(
        availability: .disabled,
        snapshotData: nil,
        verificationScore: nil,
        matchedTokens: [],
        summary: "Look Around verification is turned off in Settings."
    )

    static let unavailable = LookAroundPreview(
        availability: .unavailable,
        snapshotData: nil,
        verificationScore: nil,
        matchedTokens: [],
        summary: "Look Around is not available for this place."
    )
}

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
    var lookAroundPreview: LookAroundPreview = .disabled

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
    var cuisineTags: [String] = []
}
