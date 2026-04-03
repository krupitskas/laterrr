import Foundation
import WebKit

struct TikTokCaptionPayload: Sendable {
    let sourceURL: URL
    let resolvedURL: URL
    let description: String
}

enum TikTokDescriptionExtractor {
    fileprivate static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    fileprivate static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

    enum ExtractionError: LocalizedError {
        case invalidResponse
        case descriptionUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "laterrr could not load that TikTok link right now."
            case .descriptionUnavailable:
                return "laterrr found the TikTok page, but it could not read the video description."
            }
        }
    }

    static func extract(from sourceURL: URL) async throws -> TikTokCaptionPayload {
        var resolvedURL = sourceURL
        var candidates: [String] = []
        var loadedPageSuccessfully = false

        if let fetchedPage = try? await fetchHTML(from: sourceURL, userAgent: mobileUserAgent) {
            loadedPageSuccessfully = true
            resolvedURL = fetchedPage.resolvedURL
            candidates.append(contentsOf: descriptionCandidates(fromHTML: fetchedPage.html))

            if let description = bestDescription(from: candidates), shouldAccept(description) {
                return TikTokCaptionPayload(
                    sourceURL: sourceURL,
                    resolvedURL: resolvedURL,
                    description: description
                )
            }
        }

        if let fetchedPage = try? await fetchHTML(from: resolvedURL, userAgent: desktopUserAgent) {
            loadedPageSuccessfully = true
            resolvedURL = fetchedPage.resolvedURL
            candidates.append(contentsOf: descriptionCandidates(fromHTML: fetchedPage.html))

            if let description = bestDescription(from: candidates), shouldAccept(description) {
                return TikTokCaptionPayload(
                    sourceURL: sourceURL,
                    resolvedURL: resolvedURL,
                    description: description
                )
            }
        }

        if let hydratedPage = try? await TikTokHydratedPageLoader.load(from: resolvedURL) {
            loadedPageSuccessfully = true
            resolvedURL = hydratedPage.resolvedURL
            candidates.append(contentsOf: descriptionCandidates(fromHydratedPage: hydratedPage))
        }

        guard let description = bestDescription(from: candidates) else {
            throw loadedPageSuccessfully ? ExtractionError.descriptionUnavailable : ExtractionError.invalidResponse
        }

        return TikTokCaptionPayload(
            sourceURL: sourceURL,
            resolvedURL: resolvedURL,
            description: description
        )
    }

    static func extractedDescription(from html: String, visibleText: String? = nil) -> String? {
        var candidates = descriptionCandidates(fromHTML: html)

        if let visibleText {
            candidates.append(contentsOf: descriptionCandidates(fromVisibleText: visibleText))
        }

        return bestDescription(from: candidates)
    }

    private static func fetchHTML(from sourceURL: URL, userAgent: String) async throws -> TikTokFetchedPage {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard
            let httpResponse = response as? HTTPURLResponse,
            (200...399).contains(httpResponse.statusCode),
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        else {
            throw ExtractionError.invalidResponse
        }

        let responseURL = response.url ?? sourceURL
        let resolvedURL = canonicalURL(from: html, baseURL: responseURL) ?? responseURL
        return TikTokFetchedPage(html: html, resolvedURL: resolvedURL)
    }

    private static func descriptionCandidates(fromHTML html: String) -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: descriptionsFromUniversalData(in: html))

        let patterns = [
            #"<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:description["']"#,
            #"<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+name=["']description["']"#,
            #""description":"(.*?)""#
        ]

        for pattern in patterns {
            if let match = firstCapture(for: pattern, in: html) {
                let decodedMatch = normalizedDescription(from: match)
                if !decodedMatch.isEmpty {
                    candidates.append(decodedMatch)
                }
            }
        }

        return uniqueCandidates(candidates)
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

        let shouldDecodeHTML = escapedDescription.contains("&") || escapedDescription.contains("<")

        let htmlDecoded: String
        if
            shouldDecodeHTML,
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

    private static func descriptionsFromUniversalData(in html: String) -> [String] {
        guard
            let scriptPayload = firstCapture(
                for: #"<script[^>]+id=["']__UNIVERSAL_DATA_FOR_REHYDRATION__["'][^>]*>(.*?)</script>"#,
                in: html
            )
        else {
            return []
        }

        return descriptionsFromUniversalDataScript(scriptPayload)
    }

    private static func descriptionsFromUniversalDataScript(_ scriptPayload: String) -> [String] {
        guard
            let data = scriptPayload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

        var candidates: [String] = []
        let candidatePaths = [
            [
                "__DEFAULT_SCOPE__",
                "webapp",
                "reflow",
                "video",
                "detail",
                "itemInfo",
                "itemStruct",
                "desc"
            ],
            [
                "__DEFAULT_SCOPE__",
                "webapp",
                "reflow",
                "video",
                "detail",
                "shareMeta",
                "desc"
            ],
            [
                "__DEFAULT_SCOPE__",
                "webapp",
                "reflow",
                "photo",
                "detail",
                "itemInfo",
                "itemStruct",
                "desc"
            ],
            [
                "__DEFAULT_SCOPE__",
                "webapp",
                "reflow",
                "photo",
                "detail",
                "shareMeta",
                "desc"
            ]
        ]

        for path in candidatePaths {
            guard
                let description = stringValue(in: json, at: path),
                !description.isEmpty
            else {
                continue
            }

            let normalized = normalizedDescription(from: description)
            if !normalized.isEmpty {
                candidates.append(normalized)
            }
        }

        candidates.append(contentsOf: recursiveCandidateStrings(in: json))
        return uniqueCandidates(candidates)
    }

    private static func stringValue(in json: Any, at path: [String]) -> String? {
        guard let nextKey = path.first else {
            return json as? String
        }

        guard let dictionary = json as? [String: Any] else {
            return nil
        }

        guard let value = dictionary[nextKey] else {
            return nil
        }

        return stringValue(in: value, at: Array(path.dropFirst()))
    }

    private static func recursiveCandidateStrings(in json: Any, currentKey: String? = nil) -> [String] {
        let candidateKeys: Set<String> = [
            "desc",
            "description",
            "caption",
            "sharedesc",
            "sharedescription",
            "subtitle",
            "text"
        ]

        if let string = json as? String {
            guard let currentKey, candidateKeys.contains(currentKey.lowercased()) else {
                return []
            }

            let normalized = normalizedDescription(from: string)
            return normalized.isEmpty ? [] : [normalized]
        }

        if let dictionary = json as? [String: Any] {
            return dictionary.flatMap { key, value in
                recursiveCandidateStrings(in: value, currentKey: key)
            }
        }

        if let array = json as? [Any] {
            return array.flatMap { recursiveCandidateStrings(in: $0, currentKey: currentKey) }
        }

        return []
    }

    private static func canonicalURL(from html: String, baseURL: URL) -> URL? {
        let canonicalPatterns = [
            #"<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']"#,
            #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["']canonical["']"#
        ]

        for pattern in canonicalPatterns {
            if
                let match = firstCapture(for: pattern, in: html),
                let url = URL(string: match, relativeTo: baseURL)?.absoluteURL
            {
                return url
            }
        }

        guard
            let scriptPayload = firstCapture(
                for: #"<script[^>]+id=["']__UNIVERSAL_DATA_FOR_REHYDRATION__["'][^>]*>(.*?)</script>"#,
                in: html
            ),
            let data = scriptPayload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data),
            let canonical = stringValue(
                in: json,
                at: ["__DEFAULT_SCOPE__", "seo", "abtest", "canonical"]
            )
        else {
            return nil
        }

        return URL(string: canonical, relativeTo: baseURL)?.absoluteURL
    }

    private static func descriptionCandidates(fromHydratedPage page: TikTokHydratedPage) -> [String] {
        var candidates: [String] = []
        candidates.append(contentsOf: descriptionsFromUniversalDataScript(page.universalData))
        candidates.append(page.ogDescription)
        candidates.append(page.metaDescription)
        candidates.append(contentsOf: descriptionCandidates(fromVisibleText: page.bodyText))
        if !page.title.isEmpty {
            candidates.append(page.title)
        }
        return uniqueCandidates(candidates)
    }

    private static func descriptionCandidates(fromVisibleText rawText: String) -> [String] {
        let normalizedText = normalizedDescription(from: rawText)
        guard !normalizedText.isEmpty else { return [] }

        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        var candidates = [Array(lines.prefix(18)).joined(separator: "\n")]

        for index in lines.indices where isPromisingCaptionAnchor(lines[index]) {
            let upperBound = min(index + 16, lines.count)
            let snippet = Array(lines[index..<upperBound]).joined(separator: "\n")
            candidates.append(snippet)
        }

        if let hashtagIndex = lines.firstIndex(where: { $0.hasPrefix("#") }), hashtagIndex > 0 {
            let startIndex = max(hashtagIndex - 12, 0)
            let snippet = Array(lines[startIndex..<hashtagIndex]).joined(separator: "\n")
            candidates.append(snippet)
        }

        candidates.append(normalizedText)
        return uniqueCandidates(candidates)
    }

    private static func isPromisingCaptionAnchor(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if isLikelyGenericShareShell(line) {
            return false
        }

        return lowered.contains("must visit")
            || lowered.contains("best ")
            || lowered.contains("guide")
            || lowered.contains("cafe")
            || lowered.contains("cafés")
            || lowered.contains("restaurant")
            || lowered.contains("paris")
            || lowered.contains("where to")
            || lowered.contains("part one")
            || lowered.range(of: #"^\d+"#, options: .regularExpression) != nil
    }

    private static func uniqueCandidates(_ rawCandidates: [String]) -> [String] {
        var seen: Set<String> = []
        var candidates: [String] = []

        for rawCandidate in rawCandidates {
            let normalized = normalizedDescription(from: rawCandidate)
            guard !normalized.isEmpty else { continue }

            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            candidates.append(normalized)
        }

        return candidates
    }

    private static func bestDescription(from rawCandidates: [String]) -> String? {
        rawCandidates
            .map { candidate in
                (candidate, candidateScore(for: candidate))
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.count > rhs.0.count
                }
                return lhs.1 > rhs.1
            }
            .first?
            .0
    }

    private static func candidateScore(for description: String) -> Int {
        let normalized = normalizedDescription(from: description)
        guard !normalized.isEmpty else { return .min }

        let parsedRoundup = TikTokPlaceParser.parse(description: normalized)
        let lineCount = normalized.components(separatedBy: .newlines).count

        var score = min(normalized.count, 700)
        score += max(0, lineCount - 1) * 35
        score += parsedRoundup.venueNames.count * 260

        if parsedRoundup.locationHint != nil {
            score += 55
        }

        if parsedRoundup.title != "TikTok roundup" {
            score += 35
        }

        if normalized.contains("#") {
            score += 25
        }

        if isLikelyGenericShareShell(normalized) {
            score -= 1_500
        }

        if parsedRoundup.venueNames.isEmpty {
            score -= 260
        }

        if lineCount == 1 {
            score -= 120
        }

        return score
    }

    private static func shouldAccept(_ description: String) -> Bool {
        let parsedRoundup = TikTokPlaceParser.parse(description: description)
        let lineCount = description.components(separatedBy: .newlines).count

        return !isLikelyGenericShareShell(description)
            && (parsedRoundup.venueNames.count >= 2 || (parsedRoundup.venueNames.count >= 1 && lineCount >= 4))
    }

    private static func isLikelyGenericShareShell(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let genericFragments = [
            "watch this video on tiktok",
            "shared a video with you",
            "shared a post with you",
            "join tiktok",
            "open tiktok",
            "make your day",
            "discover more trending videos"
        ]

        return genericFragments.contains(where: lowered.contains)
    }
}

private struct TikTokFetchedPage {
    let html: String
    let resolvedURL: URL
}

private struct TikTokHydratedPage {
    let resolvedURL: URL
    let ogDescription: String
    let metaDescription: String
    let universalData: String
    let bodyText: String
    let title: String
}

@MainActor
private final class TikTokHydratedPageLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<TikTokHydratedPage, Error>?
    private var pollingTask: Task<Void, Never>?
    private var loadTimeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isHidden = true
        webView.customUserAgent = TikTokDescriptionExtractor.desktopUserAgent

        self.webView = webView
        super.init()
        self.webView.navigationDelegate = self
    }

    deinit {
        pollingTask?.cancel()
        loadTimeoutTask?.cancel()
    }

    static func load(from url: URL) async throws -> TikTokHydratedPage {
        let loader = TikTokHydratedPageLoader()
        return try await loader.loadPage(from: url)
    }

    private func loadPage(from url: URL) async throws -> TikTokHydratedPage {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 20
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
            loadTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(16))
                self?.timeoutIfNeeded()
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }

            for attempt in 0..<10 {
                if Task.isCancelled { return }

                if let hydratedPage = try? await snapshot() {
                    let candidates = TikTokDescriptionExtractor.extractedDescription(
                        from: "<html></html>",
                        visibleText: hydratedPage.bodyText
                    )

                    if candidates != nil || attempt >= 4 {
                        finish(with: .success(hydratedPage))
                        return
                    }
                }

                try? await Task.sleep(for: .milliseconds(700))
            }

            do {
                finish(with: .success(try await snapshot()))
            } catch {
                finish(with: .failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: .failure(error))
    }

    private func snapshot() async throws -> TikTokHydratedPage {
        let script = #"""
        (function() {
          const payload = {
            href: window.location.href || "",
            ogDescription: (document.querySelector('meta[property="og:description"]')?.content || "").slice(0, 12000),
            metaDescription: (document.querySelector('meta[name="description"]')?.content || "").slice(0, 12000),
            universalData: (document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__')?.textContent || "").slice(0, 150000),
            bodyText: (document.body?.innerText || "").slice(0, 26000),
            title: (document.title || "").slice(0, 400)
          };
          return JSON.stringify(payload);
        })();
        """#

        let jsonString = try await evaluateJavaScript(script)
        guard
            let data = jsonString.data(using: .utf8),
            let payload = try? JSONDecoder().decode(HydratedPayload.self, from: data)
        else {
            throw TikTokDescriptionExtractor.ExtractionError.descriptionUnavailable
        }

        let resolvedURL = URL(string: payload.href) ?? webView.url ?? URL(string: "https://www.tiktok.com")!

        return TikTokHydratedPage(
            resolvedURL: resolvedURL,
            ogDescription: payload.ogDescription,
            metaDescription: payload.metaDescription,
            universalData: payload.universalData,
            bodyText: payload.bodyText,
            title: payload.title
        )
    }

    private func evaluateJavaScript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let stringResult = result as? String {
                    continuation.resume(returning: stringResult)
                } else {
                    continuation.resume(throwing: TikTokDescriptionExtractor.ExtractionError.descriptionUnavailable)
                }
            }
        }
    }

    private func finish(with result: Result<TikTokHydratedPage, Error>) {
        pollingTask?.cancel()
        pollingTask = nil
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil

        guard let continuation else { return }
        self.continuation = nil

        switch result {
        case let .success(page):
            continuation.resume(returning: page)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private func timeoutIfNeeded() {
        guard continuation != nil else { return }
        finish(with: .failure(TikTokDescriptionExtractor.ExtractionError.descriptionUnavailable))
    }
}

private struct HydratedPayload: Decodable {
    let href: String
    let ogDescription: String
    let metaDescription: String
    let universalData: String
    let bodyText: String
    let title: String
}
