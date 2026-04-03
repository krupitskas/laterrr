import SwiftUI

struct TikTokImportReviewView: View {
    let reviewState: TikTokImportReviewState
    let skipAction: () -> Void
    let saveAction: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(alignment: .leading, spacing: 20) {
                header

                if let currentVenue = reviewState.currentVenue {
                    reviewCard(for: currentVenue)
                }

                footer
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(reviewState.remainingCount) places left to review")
                .font(.system(.title2, design: .rounded, weight: .black))
                .foregroundStyle(LaterrrPalette.textPrimary)

            Text(reviewState.deck.title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(LaterrrPalette.textSecondary)

            Text("Swipe left to skip, or swipe right to save into Places.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(LaterrrPalette.textSecondary)
        }
    }

    private func reviewCard(for venue: TikTokResolvedVenue) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                lookAroundHero(for: venue)

                HStack(spacing: 8) {
                    LaterrrTag(title: "TikTok")
                    LaterrrTag(title: "Apple Maps")
                    if let locationHint = reviewState.deck.locationHint {
                        LaterrrTag(title: locationHint)
                    }
                }

                Text(venue.name)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text(venue.appleMapsDescription)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text(venue.fullAddress)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textSecondary)

                Text("Imported from TikTok as “\(venue.sourceLine)” and matched in Apple Maps.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textSecondary)
            }
        }
        .offset(x: dragOffset.width)
        .rotationEffect(.degrees(Double(dragOffset.width / 18)))
        .gesture(reviewGesture)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: dragOffset)
    }

    private func lookAroundHero(for venue: TikTokResolvedVenue) -> some View {
        Group {
            if let snapshotData = venue.lookAroundSnapshotData, let image = UIImage(data: snapshotData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(LaterrrPalette.accentSoft.opacity(0.34))

                    VStack(spacing: 10) {
                        Image(systemName: "binoculars")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        Text("Look Around not available")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textPrimary)
                    }
                }
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button {
                performSkip()
            } label: {
                Label("Skip", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)

            Button {
                performSave()
            } label: {
                Label("Save", systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
    }

    private var reviewGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                if value.translation.width < -120 {
                    performSkip()
                } else if value.translation.width > 120 {
                    performSave()
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func performSkip() {
        dragOffset = .zero
        skipAction()
    }

    private func performSave() {
        dragOffset = .zero
        saveAction()
    }
}
