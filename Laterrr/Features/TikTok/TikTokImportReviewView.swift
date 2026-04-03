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
            Text("\(reviewState.remainingCount) places left to review")
                .font(LaterrrTypography.display(24))
                .foregroundStyle(LaterrrPalette.textPrimary)

            Text(reviewState.deck.title)
                .font(LaterrrTypography.headline())
                .foregroundStyle(LaterrrPalette.textSecondary)
                .lineLimit(2)

            Text("Swipe left to skip, or swipe right to save into Places.")
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.textSecondary)
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
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .lineLimit(2)

                Text(venue.appleMapsDescription)
                    .font(LaterrrTypography.headline(.subheadline))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .lineLimit(2)

                Text(venue.fullAddress)
                    .font(LaterrrTypography.body(.subheadline))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .lineLimit(2)

                Text("Imported from TikTok as “\(venue.sourceLine)” and matched in Apple Maps.")
                    .font(LaterrrTypography.caption(.subheadline))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .lineLimit(3)
            }
            .padding(18)
        }
        .frame(width: width, height: height, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.86))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.94), lineWidth: 1)
        }
        .shadow(color: LaterrrPalette.shadow, radius: 24, y: 14)
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
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LaterrrPalette.accentSoft.opacity(0.38))

                    VStack(spacing: 10) {
                        Image(systemName: "binoculars")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        Text("Look Around not available")
                            .font(LaterrrTypography.headline())
                            .foregroundStyle(LaterrrPalette.textPrimary)
                    }
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 34,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 34
            )
        )
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                skipAction()
            } label: {
                Label("Skip", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                saveAction()
            } label: {
                Label("Save", systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
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
