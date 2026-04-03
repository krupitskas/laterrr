import Foundation

enum SavedPlaceSource: String, Codable, CaseIterable, Sendable {
    case camera
    case photoLibrary
    case tiktok

    var title: String {
        switch self {
        case .camera:
            return "Camera"
        case .photoLibrary:
            return "Photos"
        case .tiktok:
            return "TikTok"
        }
    }
}
