import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tikTokImportCoordinator: TikTokImportCoordinator
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var selectedTab: RootTab = .capture
    @State private var placesPath: [PlacesRoute] = []

    // Owned here so the camera session survives tab switches and stays warm
    // for the whole app session — returning to Capture is instant.
    @StateObject private var captureViewModel = CaptureViewModel()

    // Owned here so the concierge conversation survives navigation pushes.
    @StateObject private var placesChatModel = PlacesChatModel()

    var body: some View {
        VStack(spacing: 0) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            EditorialTabBar(
                items: [
                    ("Map", RootTab.map),
                    ("Places", RootTab.places),
                    ("Capture", RootTab.capture),
                    ("Review", RootTab.review),
                    ("Settings", RootTab.settings)
                ],
                selection: $selectedTab,
                onReselect: { tab in
                    if tab == .places {
                        placesPath = []
                    }
                }
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .tint(LaterrrPalette.ink)
        .background(LaterrrPalette.canvas)
        .environmentObject(settingsStore)
        .onAppear {
            captureViewModel.onAppear()
            tikTokImportCoordinator.processPendingImportsIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            captureViewModel.cameraSession.startRunning()
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
                LaterrrPalette.canvas.opacity(0.8)
                    .ignoresSafeArea()
                    .overlay {
                        InkCard(alignment: .center) {
                            InkSpinner(size: 36)

                            Text("Importing TikTok roundup")
                                .font(LaterrrTypography.display(24))
                                .foregroundStyle(LaterrrPalette.ink)
                                .multilineTextAlignment(.center)

                            Text("laterrr is loading the TikTok link, parsing the caption on-device, and matching places in Apple Maps.")
                                .font(LaterrrTypography.body(.subheadline))
                                .foregroundStyle(LaterrrPalette.inkSecondary)
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

    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            switch selectedTab {
            case .map:
                NavigationStack {
                    SavedPlacesMapView(openPlace: openPlaceFromMap)
                }

            case .places:
                NavigationStack(path: $placesPath) {
                    PlacesListView(
                        openPlace: openPlaceFromPlaces,
                        openChat: { placesPath.append(.chat) }
                    )
                    .navigationDestination(for: PlacesRoute.self) { route in
                        switch route {
                        case let .place(placeID):
                            placeDestination(for: placeID)

                        case .chat:
                            PlacesChatView(
                                model: placesChatModel,
                                openPlace: { place in
                                    placesPath.append(.place(place.id))
                                }
                            )
                        }
                    }
                }

            case .capture:
                NavigationStack {
                    CaptureView(viewModel: captureViewModel)
                }

            case .review:
                NavigationStack {
                    ReviewTabView()
                }

            case .settings:
                NavigationStack {
                    SettingsView()
                }
            }
        }
    }

    private func openPlaceFromMap(_ place: SavedPlace) {
        showPlace(place, switchToPlacesTab: true)
    }

    private func openPlaceFromPlaces(_ place: SavedPlace) {
        showPlace(place, switchToPlacesTab: false)
    }

    private func showPlace(_ place: SavedPlace, switchToPlacesTab: Bool) {
        placesPath = [.place(place.id)]

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
    case review
    case settings
}

enum PlacesRoute: Hashable {
    case place(UUID)
    case chat
}
