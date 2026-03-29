import MapKit
import SwiftUI

struct SavedPlaceDetailView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    let place: SavedPlace

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let photoData = place.photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 250)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    }

                    GlassCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(place.name)
                                    .font(.system(size: 32, weight: .black, design: .rounded))
                                    .foregroundStyle(LaterrrPalette.textPrimary)

                                Text(place.fullAddress)
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(LaterrrPalette.textSecondary)
                            }

                            Spacer()

                            ConfidencePill(score: place.confidence)
                        }

                        HStack(spacing: 12) {
                            Label(place.category, systemImage: "fork.knife")
                            Label(place.analysisMode, systemImage: "text.viewfinder")
                            Label(place.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(LaterrrPalette.textSecondary)

                        Text(place.selectionReason)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        if !place.matchedText.isEmpty {
                            Text("Matched from: \(place.matchedText)")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(LaterrrPalette.textSecondary)
                        }
                    }

                    GlassCard {
                        Map(
                            initialPosition: .region(
                                MKCoordinateRegion(
                                    center: place.coordinate,
                                    latitudinalMeters: 700,
                                    longitudinalMeters: 700
                                )
                            ),
                            interactionModes: [.pan, .zoom]
                        ) {
                            Marker(place.name, coordinate: place.coordinate)
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }

                    GlassCard {
                        Text("Next step")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text("Open this place in \(settingsStore.preferredMapsProvider.title), or share the location with someone else.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        HStack(spacing: 12) {
                            Button {
                                MapsExporter.open(
                                    url: MapsExporter.url(for: place, provider: settingsStore.preferredMapsProvider)
                                )
                            } label: {
                                Label(settingsStore.preferredMapsProvider.title, systemImage: settingsStore.preferredMapsProvider.systemImage)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)

                            if let exportURL = MapsExporter.url(for: place, provider: settingsStore.preferredMapsProvider) {
                                ShareLink(item: exportURL) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.glass)
                            }
                        }

                        if let websiteURL = place.websiteURL {
                            Link(destination: websiteURL) {
                                Label("Venue Website", systemImage: "safari")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
