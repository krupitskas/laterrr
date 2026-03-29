import SwiftData
import SwiftUI

@main
struct LaterrrApp: App {
    @StateObject private var settingsStore = SettingsStore()
    private let modelContainer = LaterrrModelContainer.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settingsStore)
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
