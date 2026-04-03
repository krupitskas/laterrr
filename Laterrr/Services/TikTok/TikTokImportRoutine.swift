import Foundation

struct TikTokImportReviewDeck: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let caption: String
    let sourceURL: URL
    let resolvedURL: URL
    let locationHint: String?
    let venues: [TikTokResolvedVenue]
}

enum TikTokImportRoutine {
    enum ImportError: LocalizedError {
        case noVenueNames
        case noResolvedVenues

        var errorDescription: String? {
            switch self {
            case .noVenueNames:
                return "laterrr read the TikTok description, but no places were found. For now, add one place after each 📍 marker."
            case .noResolvedVenues:
                return "laterrr read the TikTok description, but Apple Maps could not confirm any venues from it."
            }
        }
    }

    static func buildReviewDeck(from sourceURL: URL) async throws -> TikTokImportReviewDeck {
        let captionPayload = try await TikTokDescriptionExtractor.extract(from: sourceURL)
        let parsedRoundup = TikTokPlaceParser.parse(description: captionPayload.description)

        guard !parsedRoundup.venueNames.isEmpty else {
            throw ImportError.noVenueNames
        }

        let resolver = TikTokVenueResolver()
        let venues = await resolver.resolve(parsedRoundup: parsedRoundup)

        guard !venues.isEmpty else {
            throw ImportError.noResolvedVenues
        }

        return TikTokImportReviewDeck(
            title: parsedRoundup.title,
            caption: parsedRoundup.caption,
            sourceURL: sourceURL,
            resolvedURL: captionPayload.resolvedURL,
            locationHint: parsedRoundup.locationHint,
            venues: venues
        )
    }
}
