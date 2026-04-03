import Foundation

final class VenueMatcher {
    static let analysisMethodTitle = "On-device OCR + local matching"

    func rank(
        candidates: [VenueCandidate],
        extractedText: [String]
    ) -> (suggestions: [PlaceSuggestion], analysisMethod: String, narrative: String) {
        let suggestions = rankHeuristically(candidates: candidates, extractedText: extractedText)
        return (
            suggestions,
            Self.analysisMethodTitle,
            heuristicNarrative(for: suggestions, extractedText: extractedText)
        )
    }

    func rankHeuristically(candidates: [VenueCandidate], extractedText: [String]) -> [PlaceSuggestion] {
        let normalizedText = extractedText.map { $0.lowercased() }

        let rankedSuggestions = candidates
            .map { candidate in
                let evidence = matchEvidence(for: candidate, extractedText: normalizedText)
                let score = score(for: candidate, evidence: evidence, extractedText: normalizedText)
                let rationale = rationale(for: candidate, evidence: evidence)

                return PlaceSuggestion(
                    candidate: candidate,
                    score: score,
                    rationale: rationale,
                    matchedTokens: evidence.matchedTokens
                )
            }
            .sorted { lhs, rhs in
                let lhsHasMatch = !lhs.matchedTokens.isEmpty
                let rhsHasMatch = !rhs.matchedTokens.isEmpty

                if lhsHasMatch != rhsHasMatch {
                    return lhsHasMatch && !rhsHasMatch
                }

                if lhs.score == rhs.score {
                    return lhs.distanceMeters < rhs.distanceMeters
                }

                return lhs.score > rhs.score
            }

        return rankedSuggestions
            .filter { shouldKeep($0, extractedText: normalizedText) }
            .prefix(5)
            .map { $0 }
    }

    static func matchingSummary() -> String {
        "laterrr uses on-device text recognition and nearby map search. Exact sign matches are prioritized, and far-away results are filtered out before suggestions appear."
    }

    private func heuristicNarrative(for suggestions: [PlaceSuggestion], extractedText: [String]) -> String {
        guard let topSuggestion = suggestions.first else {
            if extractedText.isEmpty {
                return "No readable storefront text yet, so laterrr needs a clearer photo or location context."
            }

            return "laterrr read sign text but could not find a believable nearby match. Try a clearer storefront shot or move closer to the entrance."
        }

        if topSuggestion.matchedTokens.isEmpty {
            return "\(topSuggestion.name) is the closest plausible nearby place, but the sign text did not line up strongly enough for a higher-confidence guess."
        }

        let matchedText = topSuggestion.matchedTokens.joined(separator: ", ")
        if topSuggestion.distanceMeters > 0 {
            return "\(topSuggestion.name) matched sign text (\(matchedText)) and is about \(Int(topSuggestion.distanceMeters.rounded())) meters away."
        }

        return "\(topSuggestion.name) matched sign text (\(matchedText)) and is the strongest nearby result."
    }

    private func matchEvidence(for candidate: VenueCandidate, extractedText: [String]) -> MatchEvidence {
        let nameTokens = VenueTextRecognizer.normalizedTokens(from: [candidate.name])
        let normalizedName = nameTokens.joined(separator: " ")
        let normalizedQuery = extractedText.joined(separator: " ")

        let exactTokens = extractedText.filter { nameTokens.contains($0) }
        let partialTokens = extractedText.filter { extractedToken in
            guard !exactTokens.contains(extractedToken) else { return false }
            return nameTokens.contains(where: { nameToken in
                nameToken.contains(extractedToken) || extractedToken.contains(nameToken)
            })
        }

        return MatchEvidence(
            exactTokens: exactTokens,
            partialTokens: partialTokens,
            phraseMatch: !normalizedQuery.isEmpty && normalizedName.contains(normalizedQuery)
        )
    }

    private func score(
        for candidate: VenueCandidate,
        evidence: MatchEvidence,
        extractedText: [String]
    ) -> Double {
        let hasText = !extractedText.isEmpty
        let hasStrongTextMatch = evidence.hasStrongTextMatch
        let distanceBonus = distanceScore(for: candidate.distanceMeters, hasStrongTextMatch: hasStrongTextMatch)
        let categoryBonus = isFoodCategory(candidate.category) ? 0.05 : 0.0

        if !hasText {
            return min(0.88, max(0.12, 0.34 + distanceBonus + categoryBonus))
        }

        let textCoverage = Double((evidence.exactTokens.count * 2) + evidence.partialTokens.count)
            / Double(max(extractedText.count * 2, 1))
        let phraseBonus = evidence.phraseMatch ? 0.18 : 0.0
        let categoryLift = hasStrongTextMatch ? categoryBonus : 0.0
        let noMatchPenalty = hasStrongTextMatch ? 0.0 : (candidate.distanceMeters > 160 ? 0.34 : 0.18)
        let rawScore = 0.10 + (textCoverage * 0.68) + phraseBonus + distanceBonus + categoryLift - noMatchPenalty

        return min(0.99, max(0.05, rawScore))
    }

    private func rationale(for candidate: VenueCandidate, evidence: MatchEvidence) -> String {
        let distanceDescription: String
        if candidate.distanceMeters > 0 {
            distanceDescription = "about \(Int(candidate.distanceMeters.rounded())) m away"
        } else {
            distanceDescription = "near your current position"
        }

        if !evidence.exactTokens.isEmpty {
            return "Sign text matched \(evidence.exactTokens.joined(separator: ", ")) and the place is \(distanceDescription)."
        }

        if !evidence.partialTokens.isEmpty {
            return "Sign text partially matched \(evidence.partialTokens.joined(separator: ", ")) and the place is \(distanceDescription)."
        }

        return "Closest nearby venue fit based on location and category, but without a strong sign-text match."
    }

    private func shouldKeep(_ suggestion: PlaceSuggestion, extractedText: [String]) -> Bool {
        guard !extractedText.isEmpty else {
            return suggestion.distanceMeters <= 900 && suggestion.score >= 0.30
        }

        if !suggestion.matchedTokens.isEmpty {
            return suggestion.distanceMeters <= 2_000 && suggestion.score >= 0.42
        }

        return suggestion.distanceMeters <= 120 && suggestion.score >= 0.48
    }

    private func distanceScore(for distanceMeters: Double, hasStrongTextMatch: Bool) -> Double {
        switch distanceMeters {
        case ..<75:
            return hasStrongTextMatch ? 0.24 : 0.18
        case ..<180:
            return hasStrongTextMatch ? 0.18 : 0.12
        case ..<400:
            return hasStrongTextMatch ? 0.10 : 0.04
        case ..<900:
            return hasStrongTextMatch ? 0.03 : -0.06
        case ..<1_500:
            return hasStrongTextMatch ? -0.05 : -0.18
        default:
            return hasStrongTextMatch ? -0.18 : -0.30
        }
    }

    private func isFoodCategory(_ category: String) -> Bool {
        let lowered = category.lowercased()
        return lowered.contains("cafe")
            || lowered.contains("restaurant")
            || lowered.contains("bakery")
            || lowered.contains("brewery")
            || lowered.contains("market")
            || lowered.contains("nightlife")
            || lowered.contains("food")
    }
}

private struct MatchEvidence {
    let exactTokens: [String]
    let partialTokens: [String]
    let phraseMatch: Bool

    var matchedTokens: [String] {
        var seen = Set<String>()
        return (exactTokens + partialTokens).filter { seen.insert($0).inserted }
    }

    var hasStrongTextMatch: Bool {
        !matchedTokens.isEmpty || phraseMatch
    }
}
