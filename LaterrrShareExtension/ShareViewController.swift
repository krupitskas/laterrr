import Foundation
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private var sharedURL: URL?

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem?.title = "Import"
        navigationItem.rightBarButtonItem?.isEnabled = false
        placeholder = "Send a TikTok link to laterrr for review."

        Task {
            await loadSharedURL()
        }
    }

    override func isContentValid() -> Bool {
        sharedURL != nil
    }

    override func didSelectPost() {
        guard let sharedURL else {
            extensionContext?.cancelRequest(withError: ShareExtensionError.missingURL)
            return
        }

        TikTokPendingImportStore.enqueue(url: sharedURL)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }

    @MainActor
    private func loadSharedURL() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return
        }

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if let url = await provider.loadSharedURL(), isTikTokURL(url) {
                    sharedURL = url
                    navigationItem.rightBarButtonItem?.isEnabled = true
                    validateContent()
                    return
                }

                if let text = await provider.loadSharedText(), let url = extractURL(from: text), isTikTokURL(url) {
                    sharedURL = url
                    navigationItem.rightBarButtonItem?.isEnabled = true
                    validateContent()
                    return
                }
            }
        }
    }

    private func extractURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.url
    }

    private func isTikTokURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("tiktok.com")
    }
}

private extension NSItemProvider {
    @MainActor
    func loadSharedURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    continuation.resume(returning: item as? URL)
                }
            }
        }

        return nil
    }

    @MainActor
    func loadSharedText() async -> String? {
        if hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    if let text = item as? String {
                        continuation.resume(returning: text)
                    } else if let url = item as? URL {
                        continuation.resume(returning: url.absoluteString)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        return nil
    }
}

private enum ShareExtensionError: LocalizedError {
    case missingURL

    var errorDescription: String? {
        "laterrr could not find a TikTok link in this share."
    }
}
