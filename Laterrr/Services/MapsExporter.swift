import Foundation
import UIKit

enum MapsExporter {
    static func url(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        provider: MapProvider
    ) -> URL? {
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .appleMaps:
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
                URLQueryItem(name: "q", value: [cleanedName, cleanedAddress].joined(separator: " ").trimmingCharacters(in: .whitespaces))
            ]
            return components?.url

        case .googleMaps:
            var components = URLComponents(string: "https://www.google.com/maps/search/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "query", value: [cleanedName, cleanedAddress].joined(separator: " ").trimmingCharacters(in: .whitespaces))
            ]
            return components?.url
        }
    }

    static func url(for suggestion: PlaceSuggestion, provider: MapProvider) -> URL? {
        url(
            name: suggestion.name,
            address: suggestion.fullAddress,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            provider: provider
        )
    }

    static func url(for savedPlace: SavedPlace, provider: MapProvider) -> URL? {
        url(
            name: savedPlace.name,
            address: savedPlace.fullAddress,
            latitude: savedPlace.latitude,
            longitude: savedPlace.longitude,
            provider: provider
        )
    }

    @MainActor
    static func open(url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
