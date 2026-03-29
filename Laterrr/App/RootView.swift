import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var selectedTab: RootTab = .capture

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PlacesListView()
            }
            .tabItem {
                Label("Places", systemImage: "fork.knife.circle")
            }
            .tag(RootTab.places)

            NavigationStack {
                CaptureView()
            }
            .tabItem {
                Label("Capture", systemImage: "camera.viewfinder")
            }
            .tag(RootTab.capture)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tag(RootTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(LaterrrPalette.accent)
        .environmentObject(settingsStore)
    }
}

private enum RootTab: Hashable {
    case places
    case capture
    case settings
}
