import SwiftData
import SwiftUI

struct PlacesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let openPlace: (SavedPlace) -> Void

    @StateObject private var photoReviewController = PhotoLibraryReviewController()
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var isPhotoReviewPickerPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LaterrrBackground()

                content
            }
            .navigationTitle("Places")
            .toolbar {
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
            .safeAreaInset(edge: .bottom) {
                if !savedPlaces.isEmpty {
                    HStack {
                        Spacer()
                        searchDock(maxWidth: geometry.size.width)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: isSearchExpanded) { _, isExpanded in
                if isExpanded {
                    isSearchFocused = true
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
        } else if filteredPlaces.isEmpty {
            ScrollView {
                EmptyStateView(
                    title: "No saved place matches",
                    message: "Try another cafe name or address and laterrr will filter the list instantly.",
                    systemImage: "magnifyingglass"
                )
                .padding(20)
            }
            .scrollIndicators(.hidden)
        } else {
            List {
                ForEach(filteredPlaces) { place in
                    Button {
                        openPlace(place)
                    } label: {
                        SavedPlaceRow(place: place)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(place)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
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

    private func searchDock(maxWidth: CGFloat) -> some View {
        let isActive = isSearchExpanded || !searchText.isEmpty

        return HStack(spacing: 10) {
            if isActive {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textSecondary)

                TextField("Search name or address", text: $searchText)
                    .font(LaterrrTypography.body())
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LaterrrPalette.textSecondary.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                withAnimation(.snappy(duration: 0.28)) {
                    if isActive {
                        searchText = ""
                        isSearchExpanded = false
                        isSearchFocused = false
                    } else {
                        isSearchExpanded = true
                    }
                }
            } label: {
                Image(systemName: isActive ? "xmark" : "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.90))
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.96), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, isActive ? 16 : 4)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(width: isActive ? min(maxWidth - 40, 320) : 56, alignment: .trailing)
        .glassEffect(
            Glass.regular.tint(Color.white.opacity(0.76)),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.92), lineWidth: 1)
        }
        .shadow(color: LaterrrPalette.shadow, radius: 18, y: 10)
        .animation(.snappy(duration: 0.28), value: isActive)
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

private struct SavedPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
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
        }
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
