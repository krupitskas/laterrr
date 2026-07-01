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
            MicroText("Photos review", color: LaterrrPalette.inkSecondary)

            Text(controller.progressTitle)
                .font(LaterrrTypography.display(26))
                .foregroundStyle(LaterrrPalette.ink)

            if let dayWindow = controller.deck?.dayWindow {
                MicroText(
                    "Recent photos — last \(dayWindow) days",
                    size: 9,
                    kerning: 1.5,
                    color: LaterrrPalette.inkSecondary
                )
            }

            InkProgressBar(value: controller.progressFraction)

            Text(controller.progressSummary)
                .font(LaterrrTypography.body(.footnote))
                .foregroundStyle(LaterrrPalette.inkSecondary)

            Text("Save the selected place, skip it, or scroll the nearby options if laterrr picked the wrong one.")
                .font(LaterrrTypography.body(.footnote))
                .foregroundStyle(LaterrrPalette.inkTertiary)
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
                        .foregroundStyle(LaterrrPalette.ink)
                        .lineLimit(2)

                    Text(selectedSuggestion.shortAddress)
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(LaterrrPalette.inkSecondary)
                        .lineLimit(2)

                    reasonSection(evidenceRows: evidenceRows)

                    highlightedTextSection(
                        highlightedLines: highlightedLines,
                        extractedText: candidate.analysis.extractedText
                    )

                    if candidate.analysis.narrative != selectedSuggestion.rationale {
                        Text(candidate.analysis.narrative)
                            .font(LaterrrTypography.body(.footnote))
                            .foregroundStyle(LaterrrPalette.inkSecondary)
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
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }

    private func waitingCard(width: CGFloat, height: CGFloat) -> some View {
        InkCard(alignment: .center) {
            if controller.isScanning {
                InkSpinner(size: 36)
            } else {
                CrosshatchPlaceholder()
                    .frame(width: 72, height: 72)
            }

            Text(controller.isScanning ? "Still scanning your photos" : "No more places left")
                .font(LaterrrTypography.display(26))
                .foregroundStyle(LaterrrPalette.ink)
                .multilineTextAlignment(.center)

            Text(
                controller.isScanning
                    ? "laterrr already opened the review deck and will drop the next place photo here as soon as it finds one."
                    : "The current review queue is empty."
            )
            .font(LaterrrTypography.body(.subheadline))
            .foregroundStyle(LaterrrPalette.inkSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(width: width, height: height)
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
            .disabled(controller.currentCandidate == nil)

            Button {
                saveAction()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inkPrimary)
            .disabled(controller.currentSuggestion == nil)
        }
    }

    @ViewBuilder
    private func reasonSection(evidenceRows: [EvidenceReasonItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroText("Why laterrr picked this", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)
                .padding(.bottom, 8)

            HairlineDivider()

            ForEach(Array(evidenceRows.enumerated()), id: \.element.id) { index, row in
                EvidenceReasonRow(row: row, index: index)
                HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))
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
                MicroText("Highlighted in the photo", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)

                TokenChipFlow(items: highlightedLines)
            }
        } else if !extractedText.isEmpty {
            Text("Read from photo: \(extractedText.prefix(4).joined(separator: ", "))")
                .font(LaterrrTypography.accent(16))
                .foregroundStyle(LaterrrPalette.inkSecondary)
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
                MicroText("Nearby options", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)

                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    let isSelected = selectedSuggestion.id == suggestion.id

                    Button {
                        controller.selectSuggestion(index: index)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.name)
                                    .font(LaterrrTypography.display(19))
                                    .foregroundStyle(isSelected ? LaterrrPalette.canvas : LaterrrPalette.ink)
                                    .lineLimit(1)

                                Text(suggestion.shortAddress)
                                    .font(LaterrrTypography.body(.footnote))
                                    .foregroundStyle(
                                        isSelected
                                            ? LaterrrPalette.canvas.opacity(0.7)
                                            : LaterrrPalette.inkSecondary
                                    )
                                    .lineLimit(2)
                            }

                            Spacer()

                            if isSelected {
                                MicroText("Selected", size: 9, kerning: 1.5, color: LaterrrPalette.canvas)
                            } else {
                                ConfidencePill(score: suggestion.score)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? LaterrrPalette.ink : LaterrrPalette.canvas)
                        .overlay {
                            Rectangle()
                                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
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
    var index: Int = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            MicroText(String(format: "%02d", index + 1), size: 9, kerning: 1.5, color: LaterrrPalette.inkTertiary)

            VStack(alignment: .leading, spacing: 4) {
                MicroText(row.title, size: 9, kerning: 1.5)

                Text(row.body)
                    .font(LaterrrTypography.body(.footnote))
                    .foregroundStyle(LaterrrPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                LaterrrTag(title: item)
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
            CrosshatchPattern()

            if let image {
                EvidenceImageCanvas(
                    image: image,
                    observations: Array(highlightedObservations.prefix(5))
                )
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    CrosshatchPlaceholder()
                        .frame(width: 56, height: 56)

                    Text("Preview unavailable")
                        .font(LaterrrTypography.body(.footnote))
                        .foregroundStyle(LaterrrPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                if isLoading {
                    InkSpinner(size: 16)
                }

                Text(statusText)
                    .font(LaterrrTypography.body(.caption))
                    .foregroundStyle(LaterrrPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
            .padding(12)

            VStack {
                HStack {
                    Spacer()

                    MicroText("Zoom", size: 9, kerning: 1.5)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(LaterrrPalette.canvas)
                        .overlay {
                            Rectangle()
                                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                        }
                }

                Spacer()
            }
            .padding(12)
        }
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
        .contentShape(Rectangle())
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

                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .overlay {
                            Rectangle()
                                .strokeBorder(Color.white, lineWidth: 2)
                        }
                        .overlay {
                            Rectangle()
                                .strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                                .padding(2)
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
                            .foregroundStyle(Color.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        MicroText("Close", size: 9, kerning: 1.5, color: .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay {
                                Rectangle()
                                    .strokeBorder(Color.white, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }

                ZoomableEvidenceCanvas(
                    image: UIImage(data: photoData),
                    observations: Array(highlightedObservations.prefix(8))
                )

                MicroText(
                    "Pinch to zoom · drag to inspect",
                    size: 9,
                    kerning: 1.5,
                    color: Color.white.opacity(0.6)
                )
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
                CrosshatchPattern(lineColor: .white, lineOpacity: 0.1)

                if let image {
                    EvidenceImageCanvas(image: image, observations: observations)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(dragGesture)
                        .simultaneousGesture(magnificationGesture)
                        .onTapGesture(count: 2, perform: toggleZoom)
                } else {
                    Text("Preview unavailable")
                        .font(LaterrrTypography.body(.footnote))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .overlay {
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1)
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
