import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var keepPhotoSnapshot: Bool {
        didSet { defaults.set(keepPhotoSnapshot, forKey: Keys.keepPhotoSnapshot) }
    }

    @Published var enableLookAroundVerification: Bool {
        didSet { defaults.set(enableLookAroundVerification, forKey: Keys.enableLookAroundVerification) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keepPhotoSnapshot = defaults.object(forKey: Keys.keepPhotoSnapshot) as? Bool ?? true
        self.enableLookAroundVerification = defaults.object(forKey: Keys.enableLookAroundVerification) as? Bool ?? true
    }
}

private enum Keys {
    static let keepPhotoSnapshot = "keepPhotoSnapshot"
    static let enableLookAroundVerification = "enableLookAroundVerification"
}
