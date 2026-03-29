import CoreLocation
import Foundation

enum PlaceCapturePipeline {
    static func analyze(photoData: Data, location: CLLocation?) async -> CaptureAnalysisPayload {
        let searcher = NearbyVenueSearcher()
        let matcher = VenueMatcher()

        let extractedText = await VenueTextRecognizer.recognizeText(in: photoData)
        let candidates = await searcher.searchCandidates(near: location, extractedText: extractedText)

        let ranking = matcher.rank(
            candidates: candidates,
            extractedText: extractedText
        )

        return CaptureAnalysisPayload(
            extractedText: extractedText,
            suggestions: ranking.suggestions,
            analysisMethod: ranking.analysisMethod,
            narrative: ranking.narrative
        )
    }
}
