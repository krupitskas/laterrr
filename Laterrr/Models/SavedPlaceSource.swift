import Foundation

enum SavedPlaceSource: String, Codable, CaseIterable, Sendable {
    case camera
    case tiktok

    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .tiktok:
            return "TikTok"
        }
    }
}
