import Foundation
import ImageIO
@preconcurrency import MapKit
import UIKit
import Vision

enum LookAroundVerifier {
    static func enrich(
        suggestions: [PlaceSuggestion],
        photoData: Data,
        extractedText: [String],
        isEnabled: Bool
    ) async -> [PlaceSuggestion] {
        guard !suggestions.isEmpty else {
            return suggestions
        }

        guard isEnabled else {
            return suggestions.map { suggestion in
                var updatedSuggestion = suggestion
                updatedSuggestion.lookAroundPreview = .disabled
                return updatedSuggestion
            }
        }

        var enrichedSuggestions = suggestions

        await withTaskGroup(of: (Int, LookAroundPreview).self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                group.addTask {
                    let preview = await verify(
                        suggestion: suggestion,
                        photoData: photoData,
                        extractedText: extractedText
                    )
                    return (index, preview)
                }
            }

            for await (index, preview) in group {
                enrichedSuggestions[index].lookAroundPreview = preview

                if let verificationScore = preview.verificationScore {
                    let lookAroundAdjustment = (verificationScore - 0.5) * 0.16
                    enrichedSuggestions[index].score = min(
                        0.99,
                        max(0.05, enrichedSuggestions[index].score + lookAroundAdjustment)
                    )
                }
            }
        }

        return enrichedSuggestions.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.distanceMeters < rhs.distanceMeters
            }

            return lhs.score > rhs.score
        }
    }

    private static func verify(
        suggestion: PlaceSuggestion,
        photoData: Data,
        extractedText: [String]
    ) async -> LookAroundPreview {
        guard let snapshotData = await lookAroundSnapshotData(for: suggestion.coordinate) else {
            return .unavailable
        }

        let visualScore = featurePrintSimilarityScore(
            sourceImageData: photoData,
            comparisonImageData: snapshotData
        )

        let lookAroundText = await VenueTextRecognizer.recognizeText(in: snapshotData)
        let extractedTokenSet = Set(extractedText)
        let nameTokenSet = Set(VenueTextRecognizer.normalizedTokens(from: [suggestion.name]))
        let lookAroundTokenSet = Set(lookAroundText)

        let extractedOverlap = extractedTokenSet.intersection(lookAroundTokenSet)
        let nameOverlap = nameTokenSet.intersection(lookAroundTokenSet)
        let textEvidenceScore = textScore(
            extractedOverlapCount: extractedOverlap.count,
            extractedTokenCount: extractedTokenSet.count,
            nameOverlapCount: nameOverlap.count,
            nameTokenCount: nameTokenSet.count
        )

        let verificationScore = combinedScore(
            visualScore: visualScore,
            textEvidenceScore: textEvidenceScore
        )

        let matchedTokens = Array(extractedOverlap.union(nameOverlap)).sorted()

        return LookAroundPreview(
            availability: .available,
            snapshotData: snapshotData,
            verificationScore: verificationScore,
            matchedTokens: matchedTokens,
            summary: summary(
                verificationScore: verificationScore,
                visualScore: visualScore,
                matchedTokens: matchedTokens
            )
        )
    }

    private static func combinedScore(
        visualScore: Double?,
        textEvidenceScore: Double?
    ) -> Double? {
        switch (visualScore, textEvidenceScore) {
        case let (visual?, text?):
            return min(0.99, max(0, (visual * 0.7) + (text * 0.3)))
        case let (visual?, nil):
            return visual
        case let (nil, text?):
            return text
        case (nil, nil):
            return nil
        }
    }

    private static func summary(
        verificationScore: Double?,
        visualScore: Double?,
        matchedTokens: [String]
    ) -> String {
        let scoreText: String
        if let verificationScore {
            scoreText = "\(Int((verificationScore * 100).rounded()))%"
        } else if let visualScore {
            scoreText = "\(Int((visualScore * 100).rounded()))%"
        } else {
            scoreText = "unknown"
        }

        if !matchedTokens.isEmpty {
            return "Look Around check: \(scoreText) aligned, with matching sign text \(matchedTokens.joined(separator: ", "))."
        }

        return "Look Around check: \(scoreText) visual alignment with the nearby street view."
    }

    private static func textScore(
        extractedOverlapCount: Int,
        extractedTokenCount: Int,
        nameOverlapCount: Int,
        nameTokenCount: Int
    ) -> Double? {
        var components: [Double] = []

        if extractedTokenCount > 0 {
            components.append(Double(extractedOverlapCount) / Double(extractedTokenCount))
        }

        if nameTokenCount > 0 {
            components.append(Double(nameOverlapCount) / Double(nameTokenCount))
        }

        guard !components.isEmpty else {
            return nil
        }

        return components.reduce(0, +) / Double(components.count)
    }

    private static func lookAroundSnapshotData(for coordinate: CLLocationCoordinate2D) async -> Data? {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)

        guard let scene = try? await request.scene else {
            return nil
        }

        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 720, height: 420)

        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)

        guard let snapshot = try? await snapshotter.snapshot else {
            return nil
        }

        return snapshot.image.jpegData(compressionQuality: 0.84)
    }

    private static func featurePrintSimilarityScore(
        sourceImageData: Data,
        comparisonImageData: Data
    ) -> Double? {
        guard
            let sourceFeaturePrint = featurePrintObservation(from: sourceImageData),
            let comparisonFeaturePrint = featurePrintObservation(from: comparisonImageData)
        else {
            return nil
        }

        var distance: Float = 0

        do {
            try sourceFeaturePrint.computeDistance(&distance, to: comparisonFeaturePrint)
        } catch {
            return nil
        }

        let normalizedDistance = min(max(Double(distance), 0), 40)
        return max(0, 1 - (normalizedDistance / 40))
    }

    private static func featurePrintObservation(from imageData: Data) -> VNFeaturePrintObservation? {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)

        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }
}
