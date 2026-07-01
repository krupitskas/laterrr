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
                HeadingWedge()
                    .fill(Color.black)
                    .frame(width: 12, height: 9)
                    .offset(y: -16)
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
        }
        .accessibilityLabel("Your location")
    }
}

private struct HeadingWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
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
