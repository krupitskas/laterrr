import MapKit
import SwiftUI

struct SavedPlaceDetailView: View {
    let place: SavedPlace

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.name)
                                .font(LaterrrTypography.display(32))
                                .foregroundStyle(LaterrrPalette.textPrimary)

                            Text(place.fullAddress)
                                .font(LaterrrTypography.body())
                                .foregroundStyle(LaterrrPalette.textSecondary)
                        }

                        HStack(spacing: 8) {
                            LaterrrTag(title: place.source.title)
                            LaterrrTag(title: place.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }

                        Text(place.selectionReason)
                            .font(LaterrrTypography.headline())
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        if !place.matchedText.isEmpty {
                            Text("Matched from: \(place.matchedText)")
                                .font(LaterrrTypography.body(.subheadline))
                                .foregroundStyle(LaterrrPalette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SavedPlacePreviewImage(
                        place: place,
                        width: nil,
                        height: 250,
                        cornerRadius: 34
                    )
                    .frame(maxWidth: .infinity)

                    GlassCard {
                        Map(
                            initialPosition: .region(
                                MKCoordinateRegion(
                                    center: place.coordinate,
                                    latitudinalMeters: 700,
                                    longitudinalMeters: 700
                                )
                            ),
                            interactionModes: []
                        ) {
                            Marker(place.name, coordinate: place.coordinate)
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    GlassCard {
                        Text("Apple Maps")
                            .font(LaterrrTypography.display(24))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text("Open this place in Apple Maps, or share the location with someone else.")
                            .font(LaterrrTypography.body())
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        HStack(spacing: 12) {
                            Button {
                                MapsExporter.open(
                                    url: MapsExporter.url(for: place)
                                )
                            } label: {
                                Label("Apple Maps", systemImage: "map")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)

                            if let exportURL = MapsExporter.url(for: place) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
