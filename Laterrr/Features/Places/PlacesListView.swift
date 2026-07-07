import SwiftData
import SwiftUI

struct PlacesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]

    let openPlace: (SavedPlace) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(spacing: 0) {
                header
                content
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Saved places — \(savedPlaces.count)", color: LaterrrPalette.inkSecondary)

            Text("Places.")
                .font(LaterrrTypography.display(44))
                .foregroundStyle(LaterrrPalette.ink)

            searchField
                .padding(.top, 8)

            if !availableCategories.isEmpty {
                categoryChips
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(availableCategories, id: \.self) { category in
                    categoryChip(title: category, isSelected: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
        .padding(.horizontal, -20)
        .contentMargins(.horizontal, 20, for: .scrollContent)
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MicroText(
                title,
                size: 9,
                kerning: 1.5,
                color: isSelected ? LaterrrPalette.canvas : LaterrrPalette.ink
            )
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? LaterrrPalette.ink : LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var availableCategories: [String] {
        Array(Set(savedPlaces.map(\.displayCategory).filter { !$0.isEmpty })).sorted()
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
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                TapGesture().onEnded {
                    isSearchFocused = false
                }
            )
        }
    }

    private var filteredPlaces: [SavedPlace] {
        let categoryPlaces: [SavedPlace]
        if let selectedCategory, availableCategories.contains(selectedCategory) {
            categoryPlaces = savedPlaces.filter { $0.displayCategory == selectedCategory }
        } else {
            categoryPlaces = savedPlaces
        }

        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedSearch.isEmpty else {
            return categoryPlaces
        }

        return categoryPlaces.filter { place in
            place.name.localizedCaseInsensitiveContains(normalizedSearch)
                || place.fullAddress.localizedCaseInsensitiveContains(normalizedSearch)
                || place.shortAddress.localizedCaseInsensitiveContains(normalizedSearch)
        }
    }

    private func delete(_ place: SavedPlace) {
        modelContext.delete(place)
        try? modelContext.save()
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
