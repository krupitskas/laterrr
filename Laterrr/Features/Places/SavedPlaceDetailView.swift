import MapKit
import SwiftUI

struct SavedPlaceDetailView: View {
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
                        }

                        HStack(spacing: 8) {
                            LaterrrTag(title: place.source.title)
                            LaterrrTag(title: place.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }

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
                        Text("Apple Maps")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text("Open this place in Apple Maps, or share the location with someone else.")
                            .font(.system(.body, design: .rounded))
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
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
