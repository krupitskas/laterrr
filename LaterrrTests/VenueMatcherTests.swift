import XCTest
@testable import Laterrr

final class VenueMatcherTests: XCTestCase {
    func testHeuristicRankingPrefersNameOverlap() {
        let matcher = VenueMatcher()
        let candidates = [
            VenueCandidate(
                id: "1",
                name: "Blue Bottle Coffee",
                shortAddress: "1 Main Street",
                fullAddress: "1 Main Street, Paris",
                category: "Cafe",
                latitude: 48.8566,
                longitude: 2.3522,
                distanceMeters: 45,
                websiteURL: nil,
                phoneNumber: nil
            ),
            VenueCandidate(
                id: "2",
                name: "Boulangerie du Coin",
                shortAddress: "4 Main Street",
                fullAddress: "4 Main Street, Paris",
                category: "Bakery",
                latitude: 48.8567,
                longitude: 2.3523,
                distanceMeters: 30,
                websiteURL: nil,
                phoneNumber: nil
            )
        ]

        let suggestions = matcher.rankHeuristically(
            candidates: candidates,
            extractedText: ["blue", "bottle", "coffee"]
        )

        XCTAssertEqual(suggestions.first?.name, "Blue Bottle Coffee")
        XCTAssertGreaterThan(suggestions.first?.score ?? 0, suggestions.last?.score ?? 0)
    }

    func testHeuristicRankingFiltersDistantMatchesWhenNearbyExactMatchExists() {
        let matcher = VenueMatcher()
        let candidates = [
            VenueCandidate(
                id: "near",
                name: "Picard",
                shortAddress: "12 Rue de Rivoli",
                fullAddress: "12 Rue de Rivoli, Paris",
                category: "Food Market",
                latitude: 48.8566,
                longitude: 2.3522,
                distanceMeters: 8,
                websiteURL: nil,
                phoneNumber: nil
            ),
            VenueCandidate(
                id: "far",
                name: "Picard",
                shortAddress: "Far Away",
                fullAddress: "Far Away, Paris",
                category: "Food Market",
                latitude: 48.9566,
                longitude: 2.4522,
                distanceMeters: 32_000,
                websiteURL: nil,
                phoneNumber: nil
            )
        ]

        let suggestions = matcher.rankHeuristically(
            candidates: candidates,
            extractedText: ["picard"]
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.id, "near")
        XCTAssertLessThan(suggestions.first?.distanceMeters ?? .infinity, 20)
    }

    func testGoogleMapsURLIncludesSearchQuery() {
        let url = MapsExporter.url(
            name: "Blue Bottle Coffee",
            address: "1 Main Street, Paris",
            latitude: 48.8566,
            longitude: 2.3522,
            provider: .googleMaps
        )

        XCTAssertNotNil(url)
        XCTAssertTrue(url?.absoluteString.contains("google.com/maps/search") == true)
        XCTAssertTrue(url?.absoluteString.contains("Blue%20Bottle%20Coffee") == true)
    }
}
