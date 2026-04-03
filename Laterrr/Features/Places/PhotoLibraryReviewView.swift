import SwiftUI

struct PhotoLibraryReviewView: View {
    @ObservedObject var controller: PhotoLibraryReviewController
    let skipAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = min(geometry.size.width - 40, 430)
            let cardHeight = min(max(geometry.size.height - 220, 380), 580)

            ZStack {
                LaterrrBackground()

                VStack(spacing: 16) {
                    header
                        .frame(maxWidth: cardWidth, alignment: .leading)

                    Spacer(minLength: 0)

                    if let candidate = controller.currentCandidate,
                       let selectedSuggestion = controller.currentSuggestion {
                        reviewCard(
                            for: candidate,
                            selectedSuggestion: selectedSuggestion,
                            width: cardWidth,
                            height: cardHeight
                        )
                    } else {
                        waitingCard(width: cardWidth, height: min(cardHeight, 420))
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
        VStack(alignment: .leading, spacing: 10) {
            Text(controller.progressTitle)
                .font(LaterrrTypography.display(24))
                .foregroundStyle(LaterrrPalette.textPrimary)

            if let dayWindow = controller.deck?.dayWindow {
                Text("Recent Photos from the last \(dayWindow) days")
                    .font(LaterrrTypography.headline())
                    .foregroundStyle(LaterrrPalette.textSecondary)
            }

            ProgressView(value: controller.progressFraction)
                .tint(LaterrrPalette.accent)

            Text(controller.progressSummary)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.textSecondary)

            Text("Save the selected place, skip it, or scroll the nearby options if laterrr picked the wrong one.")
                .font(LaterrrTypography.caption(.subheadline))
                .foregroundStyle(LaterrrPalette.textSecondary)
        }
    }

    private func reviewCard(
        for candidate: PhotoLibraryReviewCandidate,
        selectedSuggestion: PlaceSuggestion,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: UIImage(data: candidate.photoData) ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(height: min(height * 0.40, 220))
                .frame(maxWidth: .infinity)
                .clipped()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        LaterrrTag(title: "Photos")
                        LaterrrTag(title: candidate.capturedAt.formatted(date: .abbreviated, time: .omitted))
                    }

                    Text(selectedSuggestion.name)
                        .font(LaterrrTypography.display(28))
                        .foregroundStyle(LaterrrPalette.textPrimary)
                        .lineLimit(2)

                    Text(selectedSuggestion.shortAddress)
                        .font(LaterrrTypography.headline(.subheadline))
                        .foregroundStyle(LaterrrPalette.textSecondary)
                        .lineLimit(2)

                    if !candidate.analysis.extractedText.isEmpty {
                        Text("Read from photo: \(candidate.analysis.extractedText.prefix(4).joined(separator: ", "))")
                            .font(LaterrrTypography.caption(.subheadline))
                            .foregroundStyle(LaterrrPalette.textSecondary)
                            .lineLimit(3)
                    }

                    Text(candidate.analysis.narrative)
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(LaterrrPalette.textSecondary)

                    if !candidate.analysis.suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Nearby options")
                                .font(LaterrrTypography.caption(.subheadline))
                                .foregroundStyle(LaterrrPalette.textSecondary)

                            ForEach(Array(candidate.analysis.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                Button {
                                    controller.selectSuggestion(index: index)
                                } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(suggestion.name)
                                                .font(LaterrrTypography.headline())
                                                .foregroundStyle(LaterrrPalette.textPrimary)
                                                .lineLimit(1)

                                            Text(suggestion.shortAddress)
                                                .font(LaterrrTypography.caption(.subheadline))
                                                .foregroundStyle(LaterrrPalette.textSecondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()

                                        if selectedSuggestion.id == suggestion.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 22, weight: .semibold))
                                                .foregroundStyle(LaterrrPalette.accent)
                                        } else {
                                            ConfidencePill(score: suggestion.score)
                                        }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.white.opacity(selectedSuggestion.id == suggestion.id ? 0.76 : 0.50))
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.visible)
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
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: LaterrrPalette.shadow, radius: 24, y: 14)
    }

    private func waitingCard(width: CGFloat, height: CGFloat) -> some View {
        GlassCard(alignment: .center) {
            LaterrrBrandStar(size: 110, isSpinning: controller.isScanning)

            Text(controller.isScanning ? "Still scanning your photos" : "No more places left")
                .font(LaterrrTypography.display(26))
                .foregroundStyle(LaterrrPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                controller.isScanning
                    ? "laterrr already opened the review deck and will drop the next place photo here as soon as it finds one."
                    : "The current review queue is empty."
            )
            .font(LaterrrTypography.body())
            .foregroundStyle(LaterrrPalette.textSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(width: width, height: height)
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
            .disabled(controller.currentCandidate == nil)

            Button {
                saveAction()
            } label: {
                Label("Save", systemImage: "bookmark.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(controller.currentSuggestion == nil)
        }
    }
}
