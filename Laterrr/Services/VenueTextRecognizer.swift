import Foundation
import ImageIO
import Vision

struct RecognizedTextObservation: Identifiable, Hashable, Sendable {
    let id = UUID()
    let text: String
    let normalizedTokens: [String]
    let boundingBox: CGRect
    let confidence: Float
}

struct RecognizedTextResult: Sendable {
    let tokens: [String]
    let observations: [RecognizedTextObservation]

    static let empty = RecognizedTextResult(tokens: [], observations: [])
}

enum VenueTextRecognizer {
    private static let queue = DispatchQueue(label: "Laterrr.vision.ocr", qos: .userInitiated)

    static func recognizeText(in imageData: Data) async -> [String] {
        let result = await recognizeDetailedText(in: imageData)
        return result.tokens
    }

    static func recognizeDetailedText(in imageData: Data) async -> RecognizedTextResult {
        await withCheckedContinuation { continuation in
            queue.async {
                let detectedText = performRecognition(in: imageData)
                continuation.resume(returning: detectedText)
            }
        }
    }

    private static func performRecognition(in imageData: Data) -> RecognizedTextResult {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return .empty
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)

        do {
            try handler.perform([request])
        } catch {
            return .empty
        }

        let observations = request.results ?? []
        let detailedObservations = observations.compactMap { observation -> RecognizedTextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            return RecognizedTextObservation(
                text: text,
                normalizedTokens: normalizedTokens(from: [text]),
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }

        return RecognizedTextResult(
            tokens: Self.normalizedTokens(from: detailedObservations.map(\.text)),
            observations: detailedObservations
        )
    }

    static func normalizedTokens(from lines: [String]) -> [String] {
        let separators = CharacterSet.alphanumerics.inverted

        var seen = Set<String>()
        var tokens: [String] = []

        for line in lines {
            let rawWords = line.components(separatedBy: separators)
            for rawWord in rawWords {
                let word = rawWord
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                guard word.count >= 2 else { continue }
                guard !["menu", "open", "welcome", "the", "and"].contains(word) else { continue }

                if seen.insert(word).inserted {
                    tokens.append(word)
                }
            }
        }

        return Array(tokens.prefix(12))
    }
}
