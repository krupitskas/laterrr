import Foundation
import UIKit

enum MapsExporter {
    static func url(
        name: String,
        address: String,
        latitude: Double,
        longitude: Double
    ) -> URL? {
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: [cleanedName, cleanedAddress].joined(separator: " ").trimmingCharacters(in: .whitespaces))
        ]
        return components?.url
    }

    static func url(for suggestion: PlaceSuggestion) -> URL? {
        url(
            name: suggestion.name,
            address: suggestion.fullAddress,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude
        )
    }

    static func url(for savedPlace: SavedPlace) -> URL? {
        url(
            name: savedPlace.name,
            address: savedPlace.fullAddress,
            latitude: savedPlace.latitude,
            longitude: savedPlace.longitude
        )
    }

    @MainActor
    static func open(url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
