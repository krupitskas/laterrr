import SwiftUI

struct PhotoLibraryReviewView: View {
    @ObservedObject var controller: PhotoLibraryReviewController
    let skipAction: () -> Void
    let saveAction: () -> Void
    @State private var recognitionResult = RecognizedTextResult.empty
    @State private var isLoadingEvidence = false
    @State private var isEvidenceViewerPresented = false

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
        .task(id: controller.currentCandidate?.id) {
            await loadCurrentEvidence()
        }
        .fullScreenCover(isPresented: $isEvidenceViewerPresented) {
            if let candidate = controller.currentCandidate,
               let selectedSuggestion = controller.currentSuggestion {
                ZoomableEvidenceViewer(
                    photoData: candidate.photoData,
                    highlightedObservations: highlightedObservations(for: selectedSuggestion),
                    title: selectedSuggestion.name,
                    subtitle: photoEvidenceStatus(
                        for: selectedSuggestion,
                        highlightedLines: orderedUnique(highlightedObservations(for: selectedSuggestion).map(\.text))
                    )
                )
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
        let matchedObservations = highlightedObservations(for: selectedSuggestion)
        let highlightedLines = orderedUnique(matchedObservations.map(\.text))
        let evidenceRows = evidenceRows(
            for: candidate,
            selectedSuggestion: selectedSuggestion,
            highlightedLines: highlightedLines
        )

        return VStack(alignment: .leading, spacing: 0) {
            PhotoEvidenceHero(
                photoData: candidate.photoData,
                highlightedObservations: matchedObservations,
                statusText: photoEvidenceStatus(
                    for: selectedSuggestion,
                    highlightedLines: highlightedLines
                ),
                isLoading: isLoadingEvidence,
                tapAction: { isEvidenceViewerPresented = true }
            )
            .frame(height: min(height * 0.44, 250))
            .padding(14)

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

                    reasonSection(evidenceRows: evidenceRows)

                    highlightedTextSection(
                        highlightedLines: highlightedLines,
                        extractedText: candidate.analysis.extractedText
                    )

                    if candidate.analysis.narrative != selectedSuggestion.rationale {
                        Text(candidate.analysis.narrative)
                            .font(LaterrrTypography.body(.subheadline))
                            .foregroundStyle(LaterrrPalette.textSecondary)
                    }

                    nearbyOptionsSection(
                        suggestions: candidate.analysis.suggestions,
                        selectedSuggestion: selectedSuggestion
                    )
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

    @ViewBuilder
    private func reasonSection(evidenceRows: [EvidenceReasonItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Why laterrr picked this")
                .font(LaterrrTypography.caption(.subheadline))
                .foregroundStyle(LaterrrPalette.textSecondary)

            ForEach(evidenceRows) { row in
                EvidenceReasonRow(row: row)
            }
        }
    }

    @ViewBuilder
    private func highlightedTextSection(
        highlightedLines: [String],
        extractedText: [String]
    ) -> some View {
        if !highlightedLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Highlighted in the photo")
                    .font(LaterrrTypography.caption(.subheadline))
                    .foregroundStyle(LaterrrPalette.textSecondary)

                TokenChipFlow(items: highlightedLines)
            }
        } else if !extractedText.isEmpty {
            Text("Read from photo: \(extractedText.prefix(4).joined(separator: ", "))")
                .font(LaterrrTypography.caption(.subheadline))
                .foregroundStyle(LaterrrPalette.textSecondary)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func nearbyOptionsSection(
        suggestions: [PlaceSuggestion],
        selectedSuggestion: PlaceSuggestion
    ) -> some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nearby options")
                    .font(LaterrrTypography.caption(.subheadline))
                    .foregroundStyle(LaterrrPalette.textSecondary)

                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
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

    private func loadCurrentEvidence() async {
        recognitionResult = .empty
        isLoadingEvidence = false

        guard let candidate = controller.currentCandidate else { return }

        isLoadingEvidence = true
        let result = await VenueTextRecognizer.recognizeDetailedText(in: candidate.photoData)
        guard controller.currentCandidate?.id == candidate.id else { return }

        recognitionResult = result
        isLoadingEvidence = false
    }

    private func highlightedObservations(for suggestion: PlaceSuggestion) -> [RecognizedTextObservation] {
        let matchedTokens = Set(suggestion.matchedTokens.map { $0.lowercased() })
        guard !matchedTokens.isEmpty else { return [] }

        return recognitionResult.observations.filter { observation in
            !Set(observation.normalizedTokens).isDisjoint(with: matchedTokens)
        }
    }

    private func photoEvidenceStatus(
        for suggestion: PlaceSuggestion,
        highlightedLines: [String]
    ) -> String {
        if isLoadingEvidence {
            return "Scanning visible sign text in the full photo"
        }

        if !highlightedLines.isEmpty {
            return "Matched storefront text is highlighted on the photo"
        }

        if !recognitionResult.tokens.isEmpty {
            return "No exact text box matched, so this pick leans more on nearby Maps and distance"
        }

        if let verificationScore = suggestion.lookAroundPreview.verificationScore {
            return "No readable text here, but Look Around still aligned \(Int((verificationScore * 100).rounded()))%"
        }

        return "No readable storefront text here, so laterrr is relying on the exterior scene and nearby places"
    }

    private func evidenceRows(
        for candidate: PhotoLibraryReviewCandidate,
        selectedSuggestion: PlaceSuggestion,
        highlightedLines: [String]
    ) -> [EvidenceReasonItem] {
        var rows: [EvidenceReasonItem] = []

        if !highlightedLines.isEmpty {
            rows.append(
                EvidenceReasonItem(
                    icon: "viewfinder",
                    title: "Matched on the photo",
                    body: "\(selectedSuggestion.name) lines up with highlighted storefront text: \(highlightedLines.joined(separator: ", "))."
                )
            )
        } else if !candidate.analysis.extractedText.isEmpty {
            rows.append(
                EvidenceReasonItem(
                    icon: "text.viewfinder",
                    title: "Text read from the frame",
                    body: "laterrr read \(candidate.analysis.extractedText.prefix(5).joined(separator: ", ")), but this specific pick is leaning more on nearby Maps, venue type, and distance."
                )
            )
        } else {
            rows.append(
                EvidenceReasonItem(
                    icon: "photo",
                    title: "Visual scene fit",
                    body: "No clean storefront text was readable, so laterrr used the exterior scene, the nearby venue list, and your location to make the best guess."
                )
            )
        }

        rows.append(
            EvidenceReasonItem(
                icon: "mappin.and.ellipse",
                title: "Nearby fit",
                body: "\(selectedSuggestion.name) is about \(Int(selectedSuggestion.distanceMeters.rounded())) m away and categorized as \(selectedSuggestion.category.lowercased())."
            )
        )

        if let verificationScore = selectedSuggestion.lookAroundPreview.verificationScore {
            rows.append(
                EvidenceReasonItem(
                    icon: "binoculars",
                    title: "Look Around check",
                    body: "Street-level imagery aligned about \(Int((verificationScore * 100).rounded()))%, so it adds a small extra boost rather than deciding the match by itself."
                )
            )
        }

        rows.append(
            EvidenceReasonItem(
                icon: "sparkles",
                title: "Final reasoning",
                body: selectedSuggestion.rationale
            )
        )

        return rows
    }

    private func orderedUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

private struct EvidenceReasonItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

private struct EvidenceReasonRow: View {
    let row: EvidenceReasonItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LaterrrPalette.accent)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(LaterrrPalette.accentSoft.opacity(0.28))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(LaterrrTypography.headline(.subheadline))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text(row.body)
                    .font(LaterrrTypography.body(.footnote))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.46))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
        }
    }
}

private struct TokenChipFlow: View {
    let items: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(LaterrrTypography.caption(.footnote))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(
                        Glass.regular.tint(Color.white.opacity(0.64)),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                    }
            }
        }
    }
}

private struct PhotoEvidenceHero: View {
    let photoData: Data
    let highlightedObservations: [RecognizedTextObservation]
    let statusText: String
    let isLoading: Bool
    let tapAction: () -> Void

    var body: some View {
        let image = UIImage(data: photoData)

        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.18))

            if let image {
                EvidenceImageCanvas(
                    image: image,
                    observations: Array(highlightedObservations.prefix(5))
                )
                .padding(12)
            } else {
                ContentUnavailableView(
                    "Preview unavailable",
                    systemImage: "photo",
                    description: Text("laterrr could not load the full photo preview.")
                )
                .foregroundStyle(LaterrrPalette.textSecondary)
            }

            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(LaterrrPalette.textPrimary)
                } else {
                    Image(systemName: highlightedObservations.isEmpty ? "photo" : "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LaterrrPalette.textPrimary)
                }

                Text(statusText)
                    .font(LaterrrTypography.caption(.footnote))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassEffect(
                Glass.regular.tint(Color.white.opacity(0.70)),
                in: Capsule(style: .continuous)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
            }
            .padding(14)

            VStack {
                HStack {
                    Spacer()

                    Label("Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(LaterrrTypography.caption(.footnote))
                        .foregroundStyle(LaterrrPalette.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(
                            Glass.regular.tint(Color.white.opacity(0.68)),
                            in: Capsule(style: .continuous)
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                        }
                }

                Spacer()
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.86), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: tapAction)
    }
}

private struct EvidenceImageCanvas: View {
    let image: UIImage
    let observations: [RecognizedTextObservation]

    var body: some View {
        GeometryReader { geometry in
            let fitRect = aspectFitRect(for: image.size, in: geometry.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ForEach(observations) { observation in
                    let rect = highlightRect(for: observation.boundingBox, in: fitRect)

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LaterrrPalette.accentSoft.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.96), LaterrrPalette.accent.opacity(0.88)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                        .frame(width: max(rect.width, 34), height: max(rect.height, 22))
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private func aspectFitRect(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - scaledSize.width) / 2,
            y: (containerSize.height - scaledSize.height) / 2
        )

        return CGRect(origin: origin, size: scaledSize)
    }

    private func highlightRect(for boundingBox: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + (boundingBox.minX * imageRect.width),
            y: imageRect.minY + ((1 - boundingBox.maxY) * imageRect.height),
            width: boundingBox.width * imageRect.width,
            height: boundingBox.height * imageRect.height
        )
    }
}

private struct ZoomableEvidenceViewer: View {
    @Environment(\.dismiss) private var dismiss

    let photoData: Data
    let highlightedObservations: [RecognizedTextObservation]
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(LaterrrTypography.display(28))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)

                        Text(subtitle)
                            .font(LaterrrTypography.body(.footnote))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.14))
                            )
                    }
                    .buttonStyle(.plain)
                }

                ZoomableEvidenceCanvas(
                    image: UIImage(data: photoData),
                    observations: Array(highlightedObservations.prefix(8))
                )

                Text("Pinch to zoom and drag to inspect the storefront text.")
                    .font(LaterrrTypography.caption(.footnote))
                    .foregroundStyle(Color.white.opacity(0.74))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct ZoomableEvidenceCanvas: View {
    let image: UIImage?
    let observations: [RecognizedTextObservation]

    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                if let image {
                    EvidenceImageCanvas(image: image, observations: observations)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)
                        .onTapGesture(count: 2, perform: toggleZoom)
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "photo",
                        description: Text("laterrr could not load the zoomable photo.")
                    )
                    .foregroundStyle(Color.white.opacity(0.76))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(baseScale * value, 1), 5)
                if scale == 1 {
                    offset = .zero
                    baseOffset = .zero
                }
            }
            .onEnded { _ in
                baseScale = scale
                if scale == 1 {
                    offset = .zero
                    baseOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > 1 else {
                    offset = .zero
                    baseOffset = .zero
                    return
                }
                baseOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            if scale > 1.05 {
                scale = 1
                baseScale = 1
                offset = .zero
                baseOffset = .zero
            } else {
                scale = 2.4
                baseScale = 2.4
            }
        }
    }
}
