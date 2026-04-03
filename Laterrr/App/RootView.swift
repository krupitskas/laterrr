import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tikTokImportCoordinator: TikTokImportCoordinator
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var selectedTab: RootTab = .capture
    @State private var placesPath: [UUID] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SavedPlacesMapView(openPlace: openPlaceFromMap)
            }
            .tabItem {
                Label("Map", systemImage: "map.circle")
            }
            .tag(RootTab.map)

            NavigationStack(path: $placesPath) {
                PlacesListView(openPlace: openPlaceFromPlaces)
                    .navigationDestination(for: UUID.self) { placeID in
                        placeDestination(for: placeID)
                    }
            }
            .tabItem {
                Label("Places", systemImage: "cup.and.saucer.fill")
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
        .onAppear {
            tikTokImportCoordinator.processPendingImportsIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            tikTokImportCoordinator.processPendingImportsIfNeeded()
        }
        .fullScreenCover(item: $tikTokImportCoordinator.reviewState) { reviewState in
            TikTokImportReviewView(
                reviewState: reviewState,
                skipAction: {
                    tikTokImportCoordinator.skipCurrent()
                },
                saveAction: {
                    tikTokImportCoordinator.saveCurrent(modelContext: modelContext)
                }
            )
        }
        .overlay {
            if tikTokImportCoordinator.isImporting {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .overlay {
                        GlassCard(alignment: .center) {
                            ProgressView()
                                .tint(LaterrrPalette.accent)

                            Text("Importing TikTok roundup")
                                .font(LaterrrTypography.headline())
                                .foregroundStyle(LaterrrPalette.textPrimary)

                            Text("laterrr is loading the TikTok link, parsing the caption on-device, and matching places in Apple Maps.")
                                .font(LaterrrTypography.body())
                                .foregroundStyle(LaterrrPalette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 340)
                        .padding(24)
                    }
            }
        }
        .alert(
            "TikTok Import",
            isPresented: Binding(
                get: { tikTokImportCoordinator.alertMessage != nil },
                set: { if !$0 { tikTokImportCoordinator.dismissAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                tikTokImportCoordinator.dismissAlert()
            }
        } message: {
            Text(tikTokImportCoordinator.alertMessage ?? "")
        }
    }

    private func openPlaceFromMap(_ place: SavedPlace) {
        showPlace(place, switchToPlacesTab: true)
    }

    private func openPlaceFromPlaces(_ place: SavedPlace) {
        showPlace(place, switchToPlacesTab: false)
    }

    private func showPlace(_ place: SavedPlace, switchToPlacesTab: Bool) {
        placesPath = [place.id]

        if switchToPlacesTab {
            selectedTab = .places
        }
    }

    @ViewBuilder
    private func placeDestination(for placeID: UUID) -> some View {
        if let place = savedPlaces.first(where: { $0.id == placeID }) {
            SavedPlaceDetailView(place: place)
        } else {
            EmptyStateView(
                title: "Place unavailable",
                message: "This saved place is no longer available. Return to the list and choose another one.",
                systemImage: "cup.and.saucer.fill"
            )
            .padding(20)
        }
    }
}

private enum RootTab: Hashable {
    case map
    case places
    case capture
    case settings
}
