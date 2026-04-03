import Foundation
import NaturalLanguage

struct TikTokParsedRoundup: Sendable {
    let title: String
    let locationHint: String?
    let venueNames: [String]
    let caption: String
}

enum TikTokPlaceParser {
    static func parse(description: String) -> TikTokParsedRoundup {
        let normalizedCaption = normalize(description)
        let lines = normalizedCaption
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let title = lines.first(where: isTitleLine) ?? lines.first ?? "TikTok roundup"
        let locationHint = extractLocationHint(from: normalizedCaption, lines: lines)

        var venueNames: [String] = []

        for line in lines {
            if let candidate = candidateVenueName(from: line, locationHint: locationHint) {
                appendUnique(candidate, into: &venueNames)
            }
        }

        for entity in namedEntities(from: normalizedCaption) {
            guard let candidate = candidateVenueName(from: entity, locationHint: locationHint) else {
                continue
            }
            appendUnique(candidate, into: &venueNames)
        }

        return TikTokParsedRoundup(
            title: title,
            locationHint: locationHint,
            venueNames: venueNames,
            caption: normalizedCaption
        )
    }

    private static func normalize(_ description: String) -> String {
        description
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func candidateVenueName(from rawLine: String, locationHint: String?) -> String? {
        var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        line = line.replacingOccurrences(of: #"^[\d\.\-\)\s]+"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^[•●▪︎]+\s*"#, with: "", options: .regularExpression)
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”`"))

        guard !line.isEmpty else { return nil }
        guard !isJunkLine(line) else { return nil }
        guard !isTitleLine(line) else { return nil }

        let wordCount = line.split(whereSeparator: \.isWhitespace).count
        guard wordCount > 0, wordCount <= 6 else { return nil }

        let normalizedLine = comparisonKey(for: line)
        guard !normalizedLine.isEmpty else { return nil }

        if let locationHint, comparisonKey(for: locationHint) == normalizedLine {
            return nil
        }

        let bannedExactMatches: Set<String> = [
            "paris",
            "paris france",
            "best parisian cafes",
            "paris cafes",
            "parisian cafes",
            "best cafes in paris",
            "instagram cafes in paris"
        ]

        guard !bannedExactMatches.contains(normalizedLine) else { return nil }
        return line
    }

    private static func isTitleLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("must visit")
            || lowered.contains("would you visit first")
            || lowered.contains("mini guide")
            || lowered.contains("best cafes")
            || lowered.contains("best parisian cafes")
            || lowered.contains("part one")
            || lowered.contains("in paris")
                && lowered.split(whereSeparator: \.isWhitespace).count > 4
    }

    private static func isJunkLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.hasPrefix("#")
            || lowered.contains("|")
            || lowered.contains("http://")
            || lowered.contains("https://")
            || lowered.contains("@")
    }

    private static func extractLocationHint(from text: String, lines: [String]) -> String? {
        if let cityFromRegex = firstLocationMatch(in: text) {
            return cityFromRegex
        }

        for line in lines {
            let lowered = line.lowercased()
            if lowered.contains("#paris") || lowered.contains(" paris ") || lowered.hasSuffix(" paris") {
                return "Paris"
            }
        }

        let placeEntities = namedEntities(from: text, allowedTags: [.placeName])
        return placeEntities.first
    }

    private static func firstLocationMatch(in text: String) -> String? {
        let pattern = #"\bin ([A-ZÀ-Ý][A-Za-zÀ-ÿ' -]{2,})"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = expression.firstMatch(in: text, range: range),
            let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        let rawLocation = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return rawLocation.split(separator: "#").first.map(String.init)
    }

    private static func namedEntities(
        from text: String,
        allowedTags: Set<NLTag> = [.organizationName, .placeName]
    ) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text

        var entities: [String] = []
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .nameTypeOrLexicalClass,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, tokenRange in
            guard let tag, allowedTags.contains(tag) else {
                return true
            }

            let entity = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !entity.isEmpty {
                entities.append(entity)
            }
            return true
        }

        return entities
    }

    private static func comparisonKey(for string: String) -> String {
        VenueTextRecognizer.normalizedTokens(from: [string]).joined(separator: " ")
    }

    private static func appendUnique(_ candidate: String, into candidates: inout [String]) {
        let candidateKey = comparisonKey(for: candidate)
        guard !candidateKey.isEmpty else { return }
        guard !candidates.contains(where: { comparisonKey(for: $0) == candidateKey }) else { return }
        candidates.append(candidate)
    }
}
