import SwiftData
import SwiftUI

@main
struct LaterrrApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var tikTokImportCoordinator = TikTokImportCoordinator()
    private let modelContainer = LaterrrModelContainer.shared

    init() {
        LaterrrChrome.configureNavigationAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .font(LaterrrTypography.body())
                .environmentObject(settingsStore)
                .environmentObject(tikTokImportCoordinator)
        }
        .modelContainer(modelContainer)
    }
}

enum LaterrrModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([SavedPlace.self])

        do {
            let configuration = ModelConfiguration(
                "Laterrr",
                schema: schema,
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            do {
                let fallback = ModelConfiguration(
                    "LaterrrLocal",
                    schema: schema,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Unable to create a SwiftData container: \(error.localizedDescription)")
            }
        }
    }()
}
