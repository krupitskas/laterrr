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

            VStack(spacing: 0) {
                header
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
                LaterrrPalette.canvas.opacity(0.8)
                    .ignoresSafeArea()
                    .overlay {
                        InkCard(alignment: .center) {
                            InkSpinner(size: 36)

                            Text("Reviewing recent place photos")
                                .font(LaterrrTypography.display(26))
                                .foregroundStyle(LaterrrPalette.ink)
                                .multilineTextAlignment(.center)

                            InkProgressBar(value: photoReviewController.progressFraction)

                            Text(photoReviewController.progressSummary)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                MicroText("Saved places — \(savedPlaces.count)", color: LaterrrPalette.inkSecondary)

                Spacer()

                Button {
                    isPhotoReviewPickerPresented = true
                } label: {
                    MicroText("Review photos", size: 9, kerning: 1.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .overlay {
                            Rectangle()
                                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(photoReviewController.isPreparing)
                .accessibilityLabel("Review recent photos")
            }

            Text("Index.")
                .font(LaterrrTypography.display(44))
                .foregroundStyle(LaterrrPalette.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
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
                ForEach(Array(savedPlaces.enumerated()), id: \.element.id) { index, place in
                    SavedPlaceRow(place: place, index: index)
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
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
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
    @FocusState private var isSearchFocused: Bool

    let openPlace: (SavedPlace) -> Void

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(spacing: 0) {
                header

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
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nothing matches.")
                            .font(LaterrrTypography.display(30))
                            .foregroundStyle(LaterrrPalette.ink)

                        Text("No saved place matches “\(searchText)”. Try another name or address.")
                            .font(LaterrrTypography.body(.subheadline))
                            .foregroundStyle(LaterrrPalette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)

                    Spacer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSearchFocused = false
                        }
                } else {
                    List {
                        ForEach(Array(filteredPlaces.enumerated()), id: \.element.id) { index, place in
                            SavedPlaceRow(place: place, index: index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openPlace(place)
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.immediately)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            isSearchFocused = false
                        }
                    )
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Search — \(savedPlaces.count) places", color: LaterrrPalette.inkSecondary)

            Text("Find.")
                .font(LaterrrTypography.display(44))
                .foregroundStyle(LaterrrPalette.ink)

            searchField
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private var searchField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField(
                    "",
                    text: $searchText,
                    prompt: Text("Search name or address…")
                        .font(LaterrrTypography.accent(19))
                        .foregroundStyle(LaterrrPalette.inkTertiary)
                )
                .font(LaterrrTypography.accent(19))
                .foregroundStyle(LaterrrPalette.ink)
                .tint(LaterrrPalette.ink)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        MicroText("Clear", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }

            HairlineDivider()
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
    var index: Int = 0

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MicroText(String(format: "%02d", index + 1), color: LaterrrPalette.inkTertiary)

            SavedPlacePreviewImage(
                place: place,
                width: 56,
                height: 56,
                cornerRadius: 0
            )
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(LaterrrTypography.display(23))
                    .foregroundStyle(LaterrrPalette.ink)
                    .lineLimit(2)

                MicroText(
                    metadataLine,
                    size: 9,
                    kerning: 1.5,
                    color: LaterrrPalette.inkSecondary
                )
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private var displayName: String {
        let trimmedName = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.hasSuffix(".") ? trimmedName : trimmedName + "."
    }

    private var metadataLine: String {
        var parts = [place.source.title, place.createdAt.formatted(date: .abbreviated, time: .omitted)]

        if !place.shortAddress.isEmpty {
            parts.append(place.shortAddress)
        }

        return parts.joined(separator: " · ")
    }
}
