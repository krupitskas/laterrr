import Foundation

enum TikTokAppGroup {
    static let identifier = "group.co.amo.com.example.Laterrr.shared"
    static let pendingImportsKey = "pendingTikTokImports"
}

struct PendingTikTokImport: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceURLString: String
    let createdAt: Date

    init(id: UUID = UUID(), sourceURL: URL, createdAt: Date = .now) {
        self.id = id
        self.sourceURLString = sourceURL.absoluteString
        self.createdAt = createdAt
    }

    var sourceURL: URL? {
        URL(string: sourceURLString)
    }
}

enum TikTokPendingImportStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: TikTokAppGroup.identifier)
    }

    static func pendingImports() -> [PendingTikTokImport] {
        guard
            let data = defaults?.data(forKey: TikTokAppGroup.pendingImportsKey),
            let imports = try? JSONDecoder().decode([PendingTikTokImport].self, from: data)
        else {
            return []
        }

        return imports.sorted { $0.createdAt < $1.createdAt }
    }

    static func enqueue(url: URL) {
        var imports = pendingImports()

        guard !imports.contains(where: { $0.sourceURLString == url.absoluteString }) else {
            return
        }

        imports.append(PendingTikTokImport(sourceURL: url))
        persist(imports)
    }

    static func remove(importID: UUID) {
        let remainingImports = pendingImports().filter { $0.id != importID }
        persist(remainingImports)
    }

    private static func persist(_ imports: [PendingTikTokImport]) {
        guard let data = try? JSONEncoder().encode(imports) else { return }
        defaults?.set(data, forKey: TikTokAppGroup.pendingImportsKey)
    }
}
