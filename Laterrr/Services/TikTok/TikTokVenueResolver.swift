import CoreLocation
import Foundation
@preconcurrency import MapKit

struct TikTokResolvedVenue: Identifiable, Sendable {
    let candidate: VenueCandidate
    let sourceLine: String
    let appleMapsDescription: String
    let lookAroundSnapshotData: Data?

    var id: String { candidate.id }
    var name: String { candidate.name }
    var shortAddress: String { candidate.shortAddress }
    var fullAddress: String { candidate.fullAddress }
    var category: String { candidate.category }
    var latitude: Double { candidate.latitude }
    var longitude: Double { candidate.longitude }
    var websiteURL: URL? { candidate.websiteURL }
    var coordinate: CLLocationCoordinate2D { candidate.coordinate }
}

final class TikTokVenueResolver {
    private let citySearchRadius: CLLocationDistance = 26_000

    func resolve(parsedRoundup: TikTokParsedRoundup) async -> [TikTokResolvedVenue] {
        let searchArea = await resolveSearchArea(from: parsedRoundup.locationHint)
        let deduplicatedNames = deduplicatedVenueNames(parsedRoundup.venueNames)

        var orderedResults: [TikTokResolvedVenue] = []

        for venueName in deduplicatedNames {
            if let resolvedVenue = await resolveVenue(
                named: venueName,
                searchArea: searchArea,
                locationHint: parsedRoundup.locationHint
            ) {
                orderedResults.append(resolvedVenue)
            }
        }

        return orderedResults
    }

    private func resolveVenue(
        named venueName: String,
        searchArea: SearchArea?,
        locationHint: String?
    ) async -> TikTokResolvedVenue? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationHint.map { "\(venueName) \($0)" } ?? venueName
        request.resultTypes = .pointOfInterest

        if let searchArea {
            request.region = searchArea.region
            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }
        }

        let items = await searchItems(using: request)
        guard let bestItem = bestMatch(from: items, requestedName: venueName, centerLocation: searchArea?.centerLocation) else {
            return nil
        }

        let candidate = venueCandidate(from: bestItem, centerLocation: searchArea?.centerLocation)
        let lookAroundSnapshotData = await LookAroundSnapshotService.snapshotData(for: candidate.coordinate)

        return TikTokResolvedVenue(
            candidate: candidate,
            sourceLine: venueName,
            appleMapsDescription: appleMapsDescription(for: candidate, locationHint: locationHint),
            lookAroundSnapshotData: lookAroundSnapshotData
        )
    }

    private func resolveSearchArea(from locationHint: String?) async -> SearchArea? {
        guard let locationHint, !locationHint.isEmpty else {
            return nil
        }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = locationHint

        let items = await searchItems(using: request)
        guard let firstItem = items.first else {
            return nil
        }

        return SearchArea(
            name: locationHint,
            centerLocation: firstItem.location,
            region: MKCoordinateRegion(
                center: firstItem.location.coordinate,
                latitudinalMeters: citySearchRadius,
                longitudinalMeters: citySearchRadius
            )
        )
    }

    private func searchItems(using request: MKLocalSearch.Request) async -> [MKMapItem] {
        let search = MKLocalSearch(request: request)
        return (try? await search.start().mapItems) ?? []
    }

    private func bestMatch(
        from items: [MKMapItem],
        requestedName: String,
        centerLocation: CLLocation?
    ) -> MKMapItem? {
        let requestedTokens = Set(VenueTextRecognizer.normalizedTokens(from: [requestedName]))
        let requestedNameKey = requestedTokens.joined(separator: " ")

        return items.max { lhs, rhs in
            score(for: lhs, requestedTokens: requestedTokens, requestedNameKey: requestedNameKey, centerLocation: centerLocation)
                < score(for: rhs, requestedTokens: requestedTokens, requestedNameKey: requestedNameKey, centerLocation: centerLocation)
        }
    }

    private func score(
        for item: MKMapItem,
        requestedTokens: Set<String>,
        requestedNameKey: String,
        centerLocation: CLLocation?
    ) -> Double {
        let nameTokens = Set(VenueTextRecognizer.normalizedTokens(from: [item.name ?? ""]))
        let itemNameKey = nameTokens.joined(separator: " ")
        let overlap = Double(requestedTokens.intersection(nameTokens).count)
        let coverage = overlap / Double(max(requestedTokens.count, 1))
        let exactMatch = itemNameKey == requestedNameKey ? 0.85 : 0
        let partialMatch = itemNameKey.contains(requestedNameKey) || requestedNameKey.contains(itemNameKey) ? 0.30 : 0
        let foodBonus = isFoodCategory(item.pointOfInterestCategory?.rawValue ?? "") ? 0.22 : 0

        let distancePenalty: Double
        if let centerLocation {
            let distance = centerLocation.distance(from: item.location)
            distancePenalty = min(distance / 12_000, 0.45)
        } else {
            distancePenalty = 0
        }

        return coverage + exactMatch + partialMatch + foodBonus - distancePenalty
    }

    private func venueCandidate(from item: MKMapItem, centerLocation: CLLocation?) -> VenueCandidate {
        VenueCandidate(
            id: item.identifier?.rawValue
                ?? "\(item.name ?? "place")-\(item.location.coordinate.latitude)-\(item.location.coordinate.longitude)",
            name: item.name ?? "Unknown Place",
            shortAddress: item.address?.shortAddress ?? item.address?.fullAddress ?? "Apple Maps result",
            fullAddress: item.address?.fullAddress ?? item.address?.shortAddress ?? "Apple Maps result",
            category: item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "Venue",
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            distanceMeters: centerLocation?.distance(from: item.location) ?? 0,
            websiteURL: item.url,
            phoneNumber: item.phoneNumber
        )
    }

    private func appleMapsDescription(for candidate: VenueCandidate, locationHint: String?) -> String {
        var parts: [String] = []

        if candidate.category != "Venue" {
            parts.append(candidate.category)
        }

        parts.append(candidate.shortAddress)

        if let locationHint, !locationHint.isEmpty, !candidate.fullAddress.localizedCaseInsensitiveContains(locationHint) {
            parts.append(locationHint)
        }

        return parts.joined(separator: " • ")
    }

    private func isFoodCategory(_ category: String) -> Bool {
        let lowered = category.lowercased()
        return lowered.contains("cafe")
            || lowered.contains("restaurant")
            || lowered.contains("bakery")
            || lowered.contains("food")
            || lowered.contains("market")
            || lowered.contains("brewery")
    }

    private func deduplicatedVenueNames(_ venueNames: [String]) -> [String] {
        var seen = Set<String>()
        return venueNames.filter { venueName in
            let key = VenueTextRecognizer.normalizedTokens(from: [venueName]).joined(separator: " ")
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }
}

private struct SearchArea: Sendable {
    let name: String
    let centerLocation: CLLocation
    let region: MKCoordinateRegion
}
