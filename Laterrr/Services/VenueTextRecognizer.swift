import Foundation
import ImageIO
import Vision

enum VenueTextRecognizer {
    private static let queue = DispatchQueue(label: "Laterrr.vision.ocr", qos: .userInitiated)

    static func recognizeText(in imageData: Data) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async {
                let detectedText = performRecognition(in: imageData)
                continuation.resume(returning: detectedText)
            }
        }
    }

    private static func performRecognition(in imageData: Data) -> [String] {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return []
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
            return []
        }

        let observations = request.results ?? []
        let lines = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return Self.normalizedTokens(from: lines)
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
