import SwiftUI

struct TikTokImportReviewView: View {
    let reviewState: TikTokImportReviewState
    let skipAction: () -> Void
    let saveAction: () -> Void

    @GestureState private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(geometry.size.width - 40, 420)
            let cardHeight = min(max(geometry.size.height - 220, 320), 500)

            ZStack {
                LaterrrBackground()

                VStack(spacing: 16) {
                    header
                        .frame(maxWidth: cardWidth, alignment: .leading)

                    Spacer(minLength: 0)

                    if let currentVenue = reviewState.currentVenue {
                        reviewCard(for: currentVenue, width: cardWidth, height: cardHeight)
                    }

                    footer
                        .frame(maxWidth: cardWidth)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroText("TikTok import", color: LaterrrPalette.inkSecondary)

            Text("\(reviewState.remainingCount) places left to review")
                .font(LaterrrTypography.display(26))
                .foregroundStyle(LaterrrPalette.ink)

            Text(reviewState.deck.title)
                .font(LaterrrTypography.accent(17))
                .foregroundStyle(LaterrrPalette.inkSecondary)
                .lineLimit(2)

            MicroText(
                "Swipe left to skip · swipe right to save",
                size: 9,
                kerning: 1.5,
                color: LaterrrPalette.inkTertiary
            )
        }
    }

    private func reviewCard(for venue: TikTokResolvedVenue, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            lookAroundHero(for: venue, height: min(height * 0.50, 220))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    LaterrrTag(title: "TikTok")
                    LaterrrTag(title: "Apple Maps")

                    if let locationHint = reviewState.deck.locationHint {
                        LaterrrTag(title: locationHint)
                    }
                }
                .lineLimit(1)

                Text(venue.name)
                    .font(LaterrrTypography.display(28))
                    .foregroundStyle(LaterrrPalette.ink)
                    .lineLimit(2)

                Text(venue.appleMapsDescription)
                    .font(LaterrrTypography.headline(.subheadline))
                    .foregroundStyle(LaterrrPalette.ink)
                    .lineLimit(2)

                Text(venue.fullAddress)
                    .font(LaterrrTypography.body(.subheadline))
                    .foregroundStyle(LaterrrPalette.inkSecondary)
                    .lineLimit(2)

                Text("Imported from TikTok as “\(venue.sourceLine)” and matched in Apple Maps.")
                    .font(LaterrrTypography.accent(16))
                    .foregroundStyle(LaterrrPalette.inkSecondary)
                    .lineLimit(3)
            }
            .padding(18)
        }
        .frame(width: width, height: height, alignment: .top)
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
        .offset(x: dragOffset.width, y: min(max(dragOffset.height, -20), 20))
        .rotationEffect(.degrees(Double(dragOffset.width / 42)))
        .scaleEffect(1 - min(abs(dragOffset.width) / 1800, 0.04))
        .gesture(reviewGesture)
        .accessibilityElement(children: .combine)
    }

    private func lookAroundHero(for venue: TikTokResolvedVenue, height: CGFloat) -> some View {
        Group {
            if let snapshotData = venue.lookAroundSnapshotData, let image = UIImage(data: snapshotData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                CrosshatchPlaceholder(caption: "Look Around not available")
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                skipAction()
            } label: {
                Text("Skip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inkOutline)

            Button {
                saveAction()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inkPrimary)
        }
    }

    private var reviewGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = CGSize(
                    width: value.translation.width,
                    height: min(max(value.translation.height, -20), 20)
                )
            }
            .onEnded { value in
                if value.translation.width < -110 {
                    skipAction()
                } else if value.translation.width > 110 {
                    saveAction()
                }
            }
    }
}
