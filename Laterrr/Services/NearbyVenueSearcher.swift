import CoreLocation
import Foundation
@preconcurrency import MapKit

final class NearbyVenueSearcher {
    private let categories: [MKPointOfInterestCategory] = [
        .bakery,
        .brewery,
        .cafe,
        .foodMarket,
        .nightlife,
        .restaurant,
        .store
    ]

    private let nearbyRadius: CLLocationDistance = 700
    private let queryRadius: CLLocationDistance = 1_500
    private let unmatchedDistanceCap: CLLocationDistance = 140
    private let matchedDistanceCap: CLLocationDistance = 2_000

    func searchCandidates(near location: CLLocation?, extractedText: [String]) async -> [VenueCandidate] {
        var candidates: [VenueCandidate] = []
        let queries = suggestedQueries(from: extractedText)

        if let location {
            candidates.append(contentsOf: await resilientSearch {
                try await nearbyPointsOfInterest(around: location)
            })

            for query in queries.prefix(3) {
                candidates.append(contentsOf: await resilientSearch {
                    try await querySearch(query: query, near: location)
                })
            }
        } else {
            for query in queries.prefix(2) {
                candidates.append(contentsOf: await resilientSearch {
                    try await querySearch(query: query, near: nil)
                })
            }
        }

        return deduplicatedCandidates(
            candidates,
            referenceLocation: location,
            extractedText: extractedText
        )
    }

    private func nearbyPointsOfInterest(around location: CLLocation) async throws -> [VenueCandidate] {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: nearbyRadius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)

        let search = MKLocalSearch(request: request)
        return try await candidateSearch(search, referenceLocation: location)
    }

    private func querySearch(query: String, near location: CLLocation?) async throws -> [VenueCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest

        if let location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: queryRadius,
                longitudinalMeters: queryRadius
            )

            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }
        }

        let search = MKLocalSearch(request: request)
        return try await candidateSearch(search, referenceLocation: location)
    }

    private func candidateSearch(
        _ search: MKLocalSearch,
        referenceLocation: CLLocation?
    ) async throws -> [VenueCandidate] {
        try await withCheckedThrowingContinuation { continuation in
            search.start { response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let candidates = Self.candidates(
                        from: response?.mapItems ?? [],
                        referenceLocation: referenceLocation
                    )
                    continuation.resume(returning: candidates)
                }
            }
        }
    }

    private func suggestedQueries(from extractedText: [String]) -> [String] {
        let focusWords = extractedText.filter { $0.count > 2 }
        guard !focusWords.isEmpty else {
            return []
        }

        var queries: [String] = []
        appendQuery(focusWords.prefix(4).joined(separator: " "), into: &queries)

        if let longestToken = focusWords.max(by: { $0.count < $1.count }) {
            appendQuery(longestToken, into: &queries)
        }

        if focusWords.count >= 2 {
            appendQuery(focusWords.prefix(2).joined(separator: " "), into: &queries)
        }

        return queries
    }

    private func appendQuery(_ query: String, into queries: inout [String]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !queries.contains(trimmed) else { return }
        queries.append(trimmed)
    }

    private static func candidates(from items: [MKMapItem], referenceLocation: CLLocation?) -> [VenueCandidate] {
        items.map { item in
            let coordinate = item.location.coordinate

            return VenueCandidate(
                id: item.identifier?.rawValue
                    ?? "\(item.name ?? "place")-\(coordinate.latitude)-\(coordinate.longitude)",
                name: item.name ?? "Unknown Venue",
                shortAddress: item.address?.shortAddress ?? item.address?.fullAddress ?? "Nearby venue",
                fullAddress: item.address?.fullAddress ?? item.address?.shortAddress ?? "Nearby venue",
                category: item.pointOfInterestCategory?.rawValue.replacingOccurrences(of: "_", with: " ").capitalized ?? "Venue",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                distanceMeters: referenceLocation?.distance(from: item.location) ?? 0,
                websiteURL: item.url,
                phoneNumber: item.phoneNumber
            )
        }
    }

    private func deduplicatedCandidates(
        _ candidates: [VenueCandidate],
        referenceLocation: CLLocation?,
        extractedText: [String]
    ) -> [VenueCandidate] {
        let filteredCandidates = candidates.filter {
            isCandidateRelevant($0, referenceLocation: referenceLocation, extractedText: extractedText)
        }

        var bestCandidateByKey: [String: VenueCandidate] = [:]

        for candidate in filteredCandidates {
            let key = deduplicationKey(for: candidate)

            if let existing = bestCandidateByKey[key] {
                bestCandidateByKey[key] = betterCandidate(candidate, than: existing)
            } else {
                bestCandidateByKey[key] = candidate
            }
        }

        return bestCandidateByKey.values
            .sorted { lhs, rhs in
                let lhsMatchesText = nameMatchesExtractedText(lhs.name, extractedText: extractedText)
                let rhsMatchesText = nameMatchesExtractedText(rhs.name, extractedText: extractedText)

                if lhsMatchesText != rhsMatchesText {
                    return lhsMatchesText && !rhsMatchesText
                }

                if lhs.distanceMeters == rhs.distanceMeters {
                    return lhs.name < rhs.name
                }

                return lhs.distanceMeters < rhs.distanceMeters
            }
            .prefix(12)
            .map { $0 }
    }

    private func resilientSearch(_ operation: () async throws -> [VenueCandidate]) async -> [VenueCandidate] {
        do {
            return try await operation()
        } catch {
            return []
        }
    }

    private func isCandidateRelevant(
        _ candidate: VenueCandidate,
        referenceLocation: CLLocation?,
        extractedText: [String]
    ) -> Bool {
        guard referenceLocation != nil else {
            return true
        }

        let hasText = !extractedText.isEmpty
        let matchesText = nameMatchesExtractedText(candidate.name, extractedText: extractedText)

        if !hasText {
            return candidate.distanceMeters <= nearbyRadius
        }

        if matchesText {
            return candidate.distanceMeters <= matchedDistanceCap
        }

        return candidate.distanceMeters <= unmatchedDistanceCap
    }

    private func nameMatchesExtractedText(_ name: String, extractedText: [String]) -> Bool {
        guard !extractedText.isEmpty else {
            return false
        }

        let normalizedNameTokens = Set(VenueTextRecognizer.normalizedTokens(from: [name]))
        return extractedText.contains { token in
            normalizedNameTokens.contains(token)
                || normalizedNameTokens.contains(where: { $0.contains(token) || token.contains($0) })
        }
    }

    private func deduplicationKey(for candidate: VenueCandidate) -> String {
        let normalizedName = VenueTextRecognizer.normalizedTokens(from: [candidate.name]).joined(separator: " ")
        let latitude = String(format: "%.4f", candidate.latitude)
        let longitude = String(format: "%.4f", candidate.longitude)
        return "\(normalizedName)|\(latitude)|\(longitude)"
    }

    private func betterCandidate(_ lhs: VenueCandidate, than rhs: VenueCandidate) -> VenueCandidate {
        if lhs.distanceMeters == rhs.distanceMeters {
            return lhs.name.count <= rhs.name.count ? lhs : rhs
        }

        return lhs.distanceMeters < rhs.distanceMeters ? lhs : rhs
    }
}
