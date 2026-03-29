import SwiftData
import SwiftUI

struct PlacesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var searchText = ""

    var body: some View {
        ZStack {
            LaterrrBackground()

            if filteredPlaces.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "Your saved places land here",
                        message: "Capture a storefront, confirm the best guess, and it shows up here across your devices once iCloud is set up.",
                        systemImage: "bookmark.circle"
                    )
                    .padding(20)
                }
            } else {
                List {
                    ForEach(filteredPlaces) { place in
                        NavigationLink {
                            SavedPlaceDetailView(place: place)
                        } label: {
                            SavedPlaceRow(place: place)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deletePlaces)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Places")
        .searchable(text: $searchText, prompt: "Search places")
    }

    private var filteredPlaces: [SavedPlace] {
        guard !searchText.isEmpty else {
            return savedPlaces
        }

        return savedPlaces.filter { place in
            place.name.localizedCaseInsensitiveContains(searchText)
                || place.fullAddress.localizedCaseInsensitiveContains(searchText)
                || place.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func deletePlaces(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredPlaces[index])
        }

        try? modelContext.save()
    }
}

private struct SavedPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                if let photoData = place.photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 78, height: 78)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LaterrrPalette.accentSoft.opacity(0.55))
                        .frame(width: 78, height: 78)
                        .overlay {
                            Image(systemName: "fork.knife.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(LaterrrPalette.textPrimary)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(place.name)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Spacer()

                        ConfidencePill(score: place.confidence)
                    }

                    Text(place.shortAddress)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(LaterrrPalette.textSecondary)

                    HStack(spacing: 12) {
                        Label(place.category, systemImage: "fork.knife")
                        Label(place.createdAt.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                    }
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                }
            }
        }
    }
}
