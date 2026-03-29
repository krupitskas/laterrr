import CoreLocation
import Foundation

enum PlaceCapturePipeline {
    static func analyze(
        photoData: Data,
        location: CLLocation?,
        enableLookAroundVerification: Bool
    ) async -> CaptureAnalysisPayload {
        let searcher = NearbyVenueSearcher()
        let matcher = VenueMatcher()

        let extractedText = await VenueTextRecognizer.recognizeText(in: photoData)
        let candidates = await searcher.searchCandidates(near: location, extractedText: extractedText)

        let initialRanking = matcher.rank(
            candidates: candidates,
            extractedText: extractedText
        )

        let suggestions = await LookAroundVerifier.enrich(
            suggestions: initialRanking.suggestions,
            photoData: photoData,
            extractedText: extractedText,
            isEnabled: enableLookAroundVerification
        )

        let analysisMethod: String
        if enableLookAroundVerification,
           suggestions.contains(where: { $0.lookAroundPreview.availability == .available }) {
            analysisMethod = "\(initialRanking.analysisMethod) + Look Around"
        } else {
            analysisMethod = initialRanking.analysisMethod
        }

        return CaptureAnalysisPayload(
            extractedText: extractedText,
            suggestions: suggestions,
            analysisMethod: analysisMethod,
            narrative: initialRanking.narrative
        )
    }
}
