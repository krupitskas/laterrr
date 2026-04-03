import MapKit
import SwiftData
import SwiftUI

struct SavedPlacesMapView: View {
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var cameraPosition: MapCameraPosition = .automatic

    let openPlace: (SavedPlace) -> Void

    var body: some View {
        ZStack {
            LaterrrBackground()

            if savedPlaces.isEmpty {
                ScrollView {
                    EmptyStateView(
                        title: "Your saved map is still empty",
                        message: "Capture a cafe or restaurant and laterrr drops a pin here for quick revisits.",
                        systemImage: "cup.and.saucer.fill"
                    )
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack(spacing: 0) {
                    Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                        ForEach(savedPlaces) { place in
                            Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                                Button {
                                    openPlace(place)
                                } label: {
                                    SavedPlaceMapPin(place: place)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .onAppear(perform: updateCamera)
                    .onChange(of: savedPlaces.map(\.id)) { _, _ in
                        updateCamera()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 14)
            }
        }
        .navigationTitle("Places on Map")
    }

    private func updateCamera() {
        guard !savedPlaces.isEmpty else {
            cameraPosition = .automatic
            return
        }

        if savedPlaces.count == 1, let place = savedPlaces.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: place.coordinate,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                )
            )
            return
        }

        let latitudes = savedPlaces.map(\.latitude)
        let longitudes = savedPlaces.map(\.longitude)

        guard
            let minLatitude = latitudes.min(),
            let maxLatitude = latitudes.max(),
            let minLongitude = longitudes.min(),
            let maxLongitude = longitudes.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let latitudeDelta = max((maxLatitude - minLatitude) * 1.8, 0.01)
        let longitudeDelta = max((maxLongitude - minLongitude) * 1.8, 0.01)

        cameraPosition = .region(
            MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
            )
        )
    }
}

private struct SavedPlaceMapPin: View {
    let place: SavedPlace

    var body: some View {
        VStack(spacing: 6) {
            Text(place.name)
                .font(LaterrrTypography.caption(.caption2))
                .foregroundStyle(LaterrrPalette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(0.76)),
                    in: Capsule()
                )
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                }

            ZStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 36))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, LaterrrPalette.accent)

                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(y: -1)
            }
        }
        .shadow(color: LaterrrPalette.shadow, radius: 18, y: 10)
    }
}
