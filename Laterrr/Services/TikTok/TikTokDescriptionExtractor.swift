import Foundation

struct TikTokCaptionPayload: Sendable {
    let sourceURL: URL
    let resolvedURL: URL
    let description: String
}

enum TikTokDescriptionExtractor {
    enum ExtractionError: LocalizedError {
        case invalidResponse
        case descriptionUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Laterrr could not load that TikTok link right now."
            case .descriptionUnavailable:
                return "Laterrr found the TikTok page, but it could not read the video description."
            }
        }
    }

    static func extract(from sourceURL: URL) async throws -> TikTokCaptionPayload {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...399).contains(httpResponse.statusCode),
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        else {
            throw ExtractionError.invalidResponse
        }

        guard let description = extractedDescription(from: html) else {
            throw ExtractionError.descriptionUnavailable
        }

        return TikTokCaptionPayload(
            sourceURL: sourceURL,
            resolvedURL: response.url ?? sourceURL,
            description: description
        )
    }

    private static func extractedDescription(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#,
            #""description":"(.*?)""#
        ]

        for pattern in patterns {
            if let match = firstCapture(for: pattern, in: html) {
                let decodedMatch = normalizedDescription(from: match)
                if !decodedMatch.isEmpty {
                    return decodedMatch
                }
            }
        }

        return nil
    }

    private static func firstCapture(for pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = expression.firstMatch(in: text, options: [], range: range),
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return String(text[captureRange])
    }

    private static func normalizedDescription(from rawDescription: String) -> String {
        let escapedDescription = rawDescription
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\"", with: "\"")

        let htmlDecoded: String
        if
            let data = escapedDescription.data(using: .utf8),
            let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        {
            htmlDecoded = attributed.string
        } else {
            htmlDecoded = escapedDescription
        }

        return htmlDecoded
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
