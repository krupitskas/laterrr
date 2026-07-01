import Foundation

private struct BytePair: Hashable {
    let a: String
    let b: String

    init(tuple: [String]) {
        a = tuple[0]
        b = tuple[1]
    }
}

private extension String {
    func regexMatches(for pattern: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(location: 0, length: utf16.count)
        return expression.matches(in: self, options: [], range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: self) else {
                return nil
            }
            return String(self[swiftRange])
        }
    }
}

enum CLIPTokenizerError: LocalizedError {
    case missingMerges
    case missingVocabulary
    case invalidVocabulary
    case missingSpecialTokens

    var errorDescription: String? {
        switch self {
        case .missingMerges:
            return "laterrr could not load the MobileCLIP merge table."
        case .missingVocabulary:
            return "laterrr could not load the MobileCLIP vocabulary."
        case .invalidVocabulary:
            return "laterrr could not decode the MobileCLIP vocabulary."
        case .missingSpecialTokens:
            return "laterrr could not initialize the MobileCLIP tokenizer."
        }
    }
}

final class CLIPTokenizer {
    private let bpeRanks: [BytePair: Int]
    private let encoder: [String: Int]
    private let contextLength = 77
    private let startTokenID: Int
    private let endTokenID: Int

    init(resourceSubdirectory: String = "MobileCLIP/Tokenizer") throws {
        guard let mergesURL = Self.resourceURL(
            forResource: "clip-merges",
            withExtension: "txt",
            subdirectory: resourceSubdirectory
        ) else {
            throw CLIPTokenizerError.missingMerges
        }

        let mergesText = try String(contentsOf: mergesURL, encoding: .utf8)
        let mergesLines = mergesText.split(separator: "\n").map(String.init)
        var ranks: [BytePair: Int] = [:]
        for index in 1 ..< mergesLines.count {
            let tuple = mergesLines[index].split(separator: " ").map(String.init)
            guard tuple.count == 2 else { continue }
            ranks[BytePair(tuple: tuple)] = index - 1
        }
        bpeRanks = ranks

        guard let vocabURL = Self.resourceURL(
            forResource: "clip-vocab",
            withExtension: "json",
            subdirectory: resourceSubdirectory
        ) else {
            throw CLIPTokenizerError.missingVocabulary
        }

        let data = try Data(contentsOf: vocabURL)
        guard let vocabulary = try? JSONDecoder().decode([String: Int].self, from: data) else {
            throw CLIPTokenizerError.invalidVocabulary
        }

        encoder = vocabulary

        guard
            let startTokenID = vocabulary["<|startoftext|>"],
            let endTokenID = vocabulary["<|endoftext|>"]
        else {
            throw CLIPTokenizerError.missingSpecialTokens
        }

        self.startTokenID = startTokenID
        self.endTokenID = endTokenID
    }

    // Build phases can flatten bundle resources, so fall back to the bundle root
    // when the expected subdirectory is missing (mirrors MobileCLIPVenueScorer.bundleURL).
    private static func resourceURL(
        forResource name: String,
        withExtension fileExtension: String,
        subdirectory: String
    ) -> URL? {
        Bundle.main.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: fileExtension)
    }

    func encodeFull(text: String) -> [Int] {
        let tokenIDs = encode(text: text)
        var output = Array(repeating: 0, count: contextLength)
        output[0] = startTokenID

        if !tokenIDs.isEmpty {
            let upperBound = min(tokenIDs.count, contextLength - 2)
            for index in 0 ..< upperBound {
                output[index + 1] = tokenIDs[index]
            }
            output[min(contextLength - 1, upperBound + 1)] = endTokenID
        } else {
            output[1] = endTokenID
        }

        return output
    }

    private func encode(text: String) -> [Int] {
        tokenize(text: text).compactMap { encoder[$0] }
    }

    private func tokenize(text: String) -> [String] {
        var tokens: [String] = []
        let lowered = text.lowercased()
        for token in byteEncode(text: lowered) {
            tokens.append(contentsOf: bpe(token: token).split(separator: " ").map(String.init))
        }
        return tokens
    }

    private func byteEncode(text: String) -> [String] {
        let pattern =
            "<\\|startoftext\\|>|<\\|endoftext\\|>|'s|'t|'re|'ve|'m|'ll|'d|[\\p{L}]+|[\\p{N}]|[^\\s\\p{L}\\p{N}]+"
        return text.regexMatches(for: pattern).map { token in
            Array(token.utf8).compactMap { byteEncoder[$0] }.joined()
        }
    }

    private func bpe(token: String) -> String {
        if token.count <= 1 {
            return token + "</w>"
        }

        var word = Array(token).map(String.init)
        let last = (word.last ?? "") + "</w>"
        word.removeLast()
        word.append(last)

        var pairs = Array(getPairs(for: word))
        if pairs.isEmpty {
            return token + "</w>"
        }

        while true {
            let rankedPairs = pairs.filter { bpeRanks[$0] != nil }
            guard !rankedPairs.isEmpty else { break }

            guard let bestPair = rankedPairs.min(by: { bpeRanks[$0, default: .max] < bpeRanks[$1, default: .max] }) else {
                break
            }

            let first = bestPair.a
            let second = bestPair.b
            var rebuilt: [String] = []
            var index = 0

            while index < word.count {
                if let nextMatch = word[index ..< word.count].firstIndex(of: first) {
                    rebuilt.append(contentsOf: word[index ..< nextMatch])
                    index = nextMatch
                } else {
                    rebuilt.append(contentsOf: word[index ..< word.count])
                    break
                }

                if word[index] == first && index < word.count - 1 && word[index + 1] == second {
                    rebuilt.append(first + second)
                    index += 2
                } else {
                    rebuilt.append(word[index])
                    index += 1
                }
            }

            word = rebuilt
            if word.count == 1 {
                break
            }

            pairs = Array(getPairs(for: word))
        }

        return word.joined(separator: " ")
    }

    private func getPairs(for word: [String]) -> Set<BytePair> {
        guard word.count > 1 else { return [] }
        var pairs = Set<BytePair>()
        for index in 0 ..< word.count - 1 {
            pairs.insert(BytePair(tuple: [word[index], word[index + 1]]))
        }
        return pairs
    }
}
