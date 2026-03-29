import Foundation

enum MapProvider: String, CaseIterable, Identifiable, Codable {
    case appleMaps
    case googleMaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMaps:
            return "Apple Maps"
        case .googleMaps:
            return "Google Maps"
        }
    }

    var systemImage: String {
        switch self {
        case .appleMaps:
            return "map"
        case .googleMaps:
            return "globe.europe.africa"
        }
    }

    var summary: String {
        switch self {
        case .appleMaps:
            return "Use Apple's native place cards and routing."
        case .googleMaps:
            return "Use Google's search results and routing links."
        }
    }
}
