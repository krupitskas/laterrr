import Foundation

enum TikTokImportURLParser {
    enum ParseError: LocalizedError {
        case empty
        case invalid
        case unsupported

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Paste a TikTok link to start the import."
            case .invalid:
                return "laterrr could not read that link. Try pasting the full TikTok URL."
            case .unsupported:
                return "laterrr only supports TikTok links in this importer right now."
            }
        }
    }

    static func parse(_ rawValue: String) -> Result<URL, ParseError> {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return .failure(.empty)
        }

        let candidateText = normalizedCandidateText(from: trimmedValue)
        guard let url = extractURL(from: candidateText) ?? URL(string: candidateText) else {
            return .failure(.invalid)
        }

        guard isTikTokURL(url) else {
            return .failure(.unsupported)
        }

        return .success(url)
    }

    static func clipboardCandidate(from clipboardString: String?) -> String {
        guard let clipboardString else { return "" }
        let trimmedValue = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return "" }

        if case let .success(url) = parse(trimmedValue) {
            return url.absoluteString
        }

        return trimmedValue
    }

    static func isTikTokURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("tiktok.com")
    }

    private static func normalizedCandidateText(from rawValue: String) -> String {
        if rawValue.contains("://") {
            return rawValue
        }

        if rawValue.lowercased().contains("tiktok.com") {
            return "https://\(rawValue)"
        }

        return rawValue
    }

    private static func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }
}
