import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferredMapsProvider: MapProvider {
        didSet { defaults.set(preferredMapsProvider.rawValue, forKey: Keys.preferredMapsProvider) }
    }

    @Published var keepPhotoSnapshot: Bool {
        didSet { defaults.set(keepPhotoSnapshot, forKey: Keys.keepPhotoSnapshot) }
    }

    @Published var autoOpenMapAfterSave: Bool {
        didSet { defaults.set(autoOpenMapAfterSave, forKey: Keys.autoOpenMapAfterSave) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferredMapsProvider = MapProvider(rawValue: defaults.string(forKey: Keys.preferredMapsProvider) ?? "") ?? .appleMaps
        self.keepPhotoSnapshot = defaults.object(forKey: Keys.keepPhotoSnapshot) as? Bool ?? true
        self.autoOpenMapAfterSave = defaults.object(forKey: Keys.autoOpenMapAfterSave) as? Bool ?? false
    }
}

private enum Keys {
    static let preferredMapsProvider = "preferredMapsProvider"
    static let keepPhotoSnapshot = "keepPhotoSnapshot"
    static let autoOpenMapAfterSave = "autoOpenMapAfterSave"
}
