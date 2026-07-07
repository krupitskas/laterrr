import MapKit
import SwiftData
import SwiftUI

struct SavedPlacesMapView: View {
    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @StateObject private var locationStore = LocationStore()

    let openPlace: (SavedPlace) -> Void

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(spacing: 0) {
                header

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
                    Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                        UserAnnotation(anchor: .center) { userLocation in
                            UserLocationPin(heading: userLocation.heading?.trueHeading)
                        }

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
                    .grayscale(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button {
                            focusOnUser()
                        } label: {
                            Image(systemName: "scope")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .frame(width: 44, height: 44)
                                .background(Color.white)
                                .overlay {
                                    Rectangle()
                                        .strokeBorder(Color.black, lineWidth: 1)
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .accessibilityLabel("Center on your location")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .onAppear(perform: updateCamera)
                    .onChange(of: savedPlaces.map(\.id)) { _, _ in
                        updateCamera()
                    }
                    .onChange(of: locationStore.currentLocation) { _, _ in
                        updateCamera()
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            locationStore.requestAuthorizationIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Saved places — \(savedPlaces.count)", color: LaterrrPalette.inkSecondary)

            Text("Map.")
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

    private func focusOnUser() {
        guard let coordinate = locationStore.currentLocation?.coordinate else {
            locationStore.requestAuthorizationIfNeeded()
            return
        }

        withAnimation {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 900,
                    longitudinalMeters: 900
                )
            )
        }
    }

    private func updateCamera() {
        guard !savedPlaces.isEmpty else {
            cameraPosition = .automatic
            return
        }

        var coordinates = savedPlaces.map(\.coordinate)

        if let userCoordinate = locationStore.currentLocation?.coordinate {
            coordinates.append(userCoordinate)
        }

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1200,
                    longitudinalMeters: 1200
                )
            )
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

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

private struct UserLocationPin: View {
    let heading: Double?

    var body: some View {
        ZStack {
            if let heading {
                FieldOfViewCone()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(heading))
            }

            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)

            Circle()
                .strokeBorder(Color.black, lineWidth: 1.5)
                .frame(width: 20, height: 20)

            Circle()
                .fill(Color.black)
                .frame(width: 9, height: 9)

            Text("YOU")
                .font(LaterrrTypography.micro(8))
                .kerning(1.2)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.black)
                .offset(y: -26)
        }
        .accessibilityLabel("Your location")
    }
}

// A ~56° cone anchored at the dot, showing which way the device is facing.
private struct FieldOfViewCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: rect.width / 2,
            startAngle: .degrees(-118),
            endAngle: .degrees(-62),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct SavedPlaceMapPin: View {
    let place: SavedPlace

    var body: some View {
        VStack(spacing: 5) {
            Text(place.name.uppercased())
                .font(LaterrrTypography.micro(9))
                .kerning(1.5)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white)
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.black, lineWidth: 1)
                }

            Rectangle()
                .fill(Color.black)
                .frame(width: 1, height: 10)

            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 14, height: 14)

                Circle()
                    .fill(Color.black)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
