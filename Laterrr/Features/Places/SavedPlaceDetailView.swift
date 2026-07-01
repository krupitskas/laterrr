import MapKit
import SwiftUI

struct SavedPlaceDetailView: View {
    let place: SavedPlace

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    SavedPlacePreviewImage(
                        place: place,
                        width: nil,
                        height: 250,
                        cornerRadius: 0
                    )
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }

                    mapBlock

                    keyValueSection

                    noteSection

                    actionSection
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            MicroText("Saved place", color: LaterrrPalette.inkSecondary)

            HStack(alignment: .top, spacing: 12) {
                Text(displayName)
                    .font(LaterrrTypography.display(38))
                    .foregroundStyle(LaterrrPalette.ink)

                Spacer(minLength: 0)

                ConfidencePill(score: place.confidence)
                    .padding(.top, 8)
            }

            Text(place.fullAddress)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayName: String {
        let trimmedName = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.hasSuffix(".") ? trimmedName : trimmedName + "."
    }

    private var mapBlock: some View {
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
            Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)

                    Circle()
                        .fill(Color.black)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .grayscale(1)
        .frame(height: 260)
        .overlay {
            crosshair
        }
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var crosshair: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            Path { path in
                path.move(to: CGPoint(x: center.x, y: 0))
                path.addLine(to: CGPoint(x: center.x, y: center.y - 22))
                path.move(to: CGPoint(x: center.x, y: center.y + 22))
                path.addLine(to: CGPoint(x: center.x, y: geometry.size.height))
                path.move(to: CGPoint(x: 0, y: center.y))
                path.addLine(to: CGPoint(x: center.x - 22, y: center.y))
                path.move(to: CGPoint(x: center.x + 22, y: center.y))
                path.addLine(to: CGPoint(x: geometry.size.width, y: center.y))
            }
            .stroke(Color.black.opacity(0.4), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var keyValueSection: some View {
        VStack(spacing: 0) {
            HairlineDivider()

            InkKeyValueRow(key: "Source", value: place.source.title)
            HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))

            InkKeyValueRow(
                key: "Saved",
                value: place.createdAt.formatted(date: .abbreviated, time: .shortened)
            )
            HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))

            if !place.category.isEmpty {
                InkKeyValueRow(key: "Category", value: place.category)
                HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))
            }

            if !place.matchedText.isEmpty {
                InkKeyValueRow(key: "Matched", value: place.matchedText)
                HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))
            }

            HairlineDivider()
        }
    }

    @ViewBuilder
    private var noteSection: some View {
        if !place.selectionReason.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MicroText("Note", color: LaterrrPalette.inkSecondary)

                Text(place.selectionReason)
                    .font(LaterrrTypography.accent(19))
                    .foregroundStyle(LaterrrPalette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    MapsExporter.open(
                        url: MapsExporter.url(for: place)
                    )
                } label: {
                    Text("Directions")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.inkPrimary)

                if let exportURL = MapsExporter.url(for: place) {
                    ShareLink(item: exportURL) {
                        Text("Share")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.inkOutline)
                }
            }

            if let websiteURL = place.websiteURL {
                Button {
                    openURL(websiteURL)
                } label: {
                    Text("Website")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.inkOutline)
            }
        }
    }
}
