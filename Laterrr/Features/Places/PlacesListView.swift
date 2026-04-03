import SwiftData
import SwiftUI

struct PlacesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let openPlace: (SavedPlace) -> Void

    @StateObject private var photoReviewController = PhotoLibraryReviewController()
    @State private var isPhotoReviewPickerPresented = false

    var body: some View {
        ZStack {
            LaterrrBackground()

            content
        }
        .navigationTitle("Places")
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Places")
                        .font(LaterrrTypography.headline())
                        .foregroundStyle(LaterrrPalette.textPrimary)

                    Text("\(savedPlaces.count) saved")
                        .font(LaterrrTypography.caption(.caption2))
                        .foregroundStyle(LaterrrPalette.textSecondary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPhotoReviewPickerPresented = true
                } label: {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(LaterrrPalette.textPrimary)
                }
                .disabled(photoReviewController.isPreparing)
                .accessibilityLabel("Review recent photos")
            }
        }
        .confirmationDialog(
            "Review your recent photos",
            isPresented: $isPhotoReviewPickerPresented,
            titleVisibility: .visible
        ) {
            Button("Last 7 days") {
                startPhotoReview(dayWindow: 7)
            }

            Button("Last 14 days") {
                startPhotoReview(dayWindow: 14)
            }

            Button("Last 30 days") {
                startPhotoReview(dayWindow: 30)
            }

            Button("Last 90 days") {
                startPhotoReview(dayWindow: 90)
            }

            Button("Last 180 days") {
                startPhotoReview(dayWindow: 180)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("laterrr will scan recent photos with location data, look for place text, and build a review deck before anything is saved.")
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { photoReviewController.isPresentingReview },
                set: { if !$0 { photoReviewController.dismissReview() } }
            )
        ) {
            PhotoLibraryReviewView(
                controller: photoReviewController,
                skipAction: {
                    photoReviewController.skipCurrent()
                },
                saveAction: {
                    photoReviewController.saveCurrent(modelContext: modelContext)
                }
            )
        }
        .overlay {
            if photoReviewController.isPreparing && !photoReviewController.isPresentingReview {
                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .overlay {
                        GlassCard(alignment: .center) {
                            LaterrrBrandStar(size: 110, isSpinning: true)

                            Text("Reviewing recent place photos")
                                .font(LaterrrTypography.display(28))
                                .foregroundStyle(LaterrrPalette.textPrimary)

                            ProgressView(value: photoReviewController.progressFraction)
                                .tint(LaterrrPalette.accent)

                            Text(photoReviewController.progressSummary)
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
            "Photos Review",
            isPresented: Binding(
                get: { photoReviewController.alertMessage != nil },
                set: { if !$0 { photoReviewController.dismissAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                photoReviewController.dismissAlert()
            }
        } message: {
            Text(photoReviewController.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if savedPlaces.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "Your saved places land here",
                    message: "Capture a storefront, confirm the best guess, and it shows up here across your devices once iCloud is set up.",
                    systemImage: "cup.and.saucer.fill"
                )
                .padding(20)
            }
            .scrollIndicators(.hidden)
        } else {
            List {
                ForEach(savedPlaces) { place in
                    SavedPlaceRow(place: place)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openPlace(place)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(place)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
    }

    private func delete(_ place: SavedPlace) {
        modelContext.delete(place)
        try? modelContext.save()
    }

    private func startPhotoReview(dayWindow: Int) {
        photoReviewController.startReview(
            dayWindow: dayWindow,
            enableLookAroundVerification: settingsStore.enableLookAroundVerification
        )
    }
}

struct PlacesSearchView: View {
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var searchText = ""
    @State private var isSearchPresented = true
    @FocusState private var isSearchFocused: Bool

    let openPlace: (SavedPlace) -> Void

    var body: some View {
        ZStack {
            LaterrrBackground()

            if savedPlaces.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "No saved places yet",
                        message: "Save a few cafes or restaurants first, then search by name or address here.",
                        systemImage: "magnifyingglass"
                    )
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            } else if filteredPlaces.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .foregroundStyle(LaterrrPalette.textSecondary)
            } else {
                List {
                    ForEach(filteredPlaces) { place in
                        SavedPlaceRow(place: place)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openPlace(place)
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Search")
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .automatic,
            prompt: "Search name or address"
        )
        .searchFocused($isSearchFocused)
        .searchSuggestions {
            ForEach(Array(filteredPlaces.prefix(6))) { place in
                Text(place.name)
                    .searchCompletion(place.name)
            }
        }
        .onAppear {
            isSearchPresented = true
            isSearchFocused = true
        }
    }

    private var filteredPlaces: [SavedPlace] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSearch.isEmpty else {
            return savedPlaces
        }

        return savedPlaces.filter { place in
            place.name.localizedCaseInsensitiveContains(normalizedSearch)
                || place.fullAddress.localizedCaseInsensitiveContains(normalizedSearch)
                || place.shortAddress.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }
}

struct SavedPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            preview

            VStack(alignment: .leading, spacing: 8) {
                Text(place.name)
                    .font(LaterrrTypography.headline())
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .lineLimit(2)

                Text(place.shortAddress)
                    .font(LaterrrTypography.body(.subheadline))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    LaterrrTag(title: place.source.title)
                    LaterrrTag(title: place.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.80))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
        }
        .shadow(color: LaterrrPalette.shadow.opacity(0.72), radius: 10, y: 5)
    }

    @ViewBuilder
    private var preview: some View {
        SavedPlacePreviewImage(
            place: place,
            width: 78,
            height: 78,
            cornerRadius: 22
        )
    }
}
