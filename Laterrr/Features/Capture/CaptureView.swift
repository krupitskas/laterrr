import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CaptureView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tikTokImportCoordinator: TikTokImportCoordinator
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CaptureViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pinchBaseZoomFactor: CGFloat?
    @State private var pastedTikTokURLString = ""
    @State private var isTikTokPasteSheetPresented = false

    var body: some View {
        ZStack {
            LaterrrBackground()

            cameraOrFallback

            captureControls
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)

            if viewModel.isAnalyzing {
                analyzingOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: selectedPhotoItem) { _, newValue in
            viewModel.importPhoto(
                from: newValue,
                enableLookAroundVerification: settingsStore.enableLookAroundVerification
            )
        }
        .onChange(of: tikTokImportCoordinator.isImporting) { _, isImporting in
            if !isImporting {
                viewModel.clearBanner()
            }
        }
        .onChange(of: tikTokImportCoordinator.reviewState?.id) { _, reviewID in
            if reviewID != nil {
                viewModel.clearBanner()
            }
        }
        .sheet(item: $viewModel.reviewState) { reviewState in
            CaptureReviewSheet(
                reviewState: reviewState,
                settingsStore: settingsStore,
                saveAction: { suggestion in
                    viewModel.save(
                        suggestion: suggestion,
                        settings: settingsStore,
                        modelContext: modelContext
                    )
                },
                openAction: { suggestion in
                    MapsExporter.open(url: MapsExporter.url(for: suggestion))
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isTikTokPasteSheetPresented) {
            TikTokPasteImportSheet(
                urlString: $pastedTikTokURLString,
                importAction: handleTikTokImport
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .alert("Capture issue", isPresented: Binding(
            get: { viewModel.alertMessage != nil },
            set: { if !$0 { viewModel.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.alertMessage = nil }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .overlay(alignment: .top) {
            if let bannerMessage = viewModel.bannerMessage {
                MicroText(bannerMessage, size: 9, kerning: 1.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(LaterrrPalette.canvas)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var cameraOrFallback: some View {
        if viewModel.cameraSession.authorizationStatus == .authorized, viewModel.cameraSession.isConfigured {
            CameraPreviewView(session: viewModel.cameraSession.session)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(cameraZoomGesture)
        } else if isCameraLoading {
            viewfinderPlaceholder {
                VStack(spacing: 18) {
                    InkSpinner(size: 36, color: .white)

                    Text("loading camera")
                        .font(LaterrrTypography.display(30))
                        .foregroundStyle(Color.white)

                    Text("laterrr is warming up the camera so you can capture the place in one shot.")
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
        } else {
            viewfinderPlaceholder {
                VStack(spacing: 16) {
                    MicroText("Viewfinder", color: Color.white.opacity(0.6))

                    Text("Point at the storefront.")
                        .font(LaterrrTypography.display(36))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)

                    Text("Take a clean venue shot and laterrr checks the sign text against places nearby.")
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if viewModel.cameraSession.authorizationStatus != .authorized {
                        Text("Camera permission is off right now. You can still import a photo from your library below.")
                            .font(LaterrrTypography.body(.footnote))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                }
                .padding(24)
            }
        }
    }

    private func viewfinderPlaceholder<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            CrosshatchPattern(lineColor: .white, lineOpacity: 0.12)
                .ignoresSafeArea()

            content()
        }
    }

    private var isCameraLoading: Bool {
        let status = viewModel.cameraSession.authorizationStatus
        let hasNoError = viewModel.cameraSession.lastError == nil
        return hasNoError && (status == .notDetermined || (status == .authorized && !viewModel.cameraSession.isConfigured))
    }

    private var captureControls: some View {
        HStack(spacing: 18) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                MicroText("Photos", size: 9, kerning: 1.5)
                    .frame(width: 64, height: 40)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                viewModel.capture(
                    enableLookAroundVerification: settingsStore.enableLookAroundVerification
                )
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(LaterrrPalette.ink, lineWidth: 1.5)
                        .frame(width: 66, height: 66)

                    Circle()
                        .fill(LaterrrPalette.ink)
                        .frame(width: 50, height: 50)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.cameraSession.authorizationStatus != .authorized)
            .accessibilityLabel("Capture photo")

            Spacer()

            Button {
                pastedTikTokURLString = TikTokImportURLParser.clipboardCandidate(
                    from: UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                )
                isTikTokPasteSheetPresented = true
            } label: {
                MicroText("Link", size: 9, kerning: 1.5)
                    .frame(width: 64, height: 40)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }

    private var analyzingOverlay: some View {
        LaterrrPalette.canvas.opacity(0.8)
            .ignoresSafeArea()
            .overlay {
                InkCard(alignment: .center) {
                    InkSpinner(size: 36)

                    Text("Finding the best nearby match")
                        .font(LaterrrTypography.display(24))
                        .foregroundStyle(LaterrrPalette.ink)
                        .multilineTextAlignment(.center)

                    Text(settingsStore.enableLookAroundVerification
                         ? "laterrr is reading the sign, checking nearby places, and verifying strong candidates with Look Around where available."
                         : "laterrr is reading the sign, checking nearby places, and trimming anything that looks too far away.")
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(LaterrrPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 340)
                .padding(24)
            }
    }

    private var cameraZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let baseZoomFactor = pinchBaseZoomFactor ?? viewModel.cameraSession.displayZoomFactor
                if pinchBaseZoomFactor == nil {
                    pinchBaseZoomFactor = baseZoomFactor
                }

                viewModel.cameraSession.setDisplayZoomFactor(baseZoomFactor * scale)
            }
            .onEnded { _ in
                pinchBaseZoomFactor = nil
            }
    }

    private func handleTikTokImport(_ rawURLString: String) -> String? {
        switch tikTokImportCoordinator.enqueueImport(from: rawURLString) {
        case let .success(outcome):
            switch outcome {
            case .started:
                break
            case .queued:
                viewModel.showBanner("TikTok list queued for review.")
            }
            return nil
        case let .failure(error):
            return error.localizedDescription
        }
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct TikTokPasteImportSheet: View {
    @Binding var urlString: String

    let importAction: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(alignment: .leading, spacing: 16) {
                MicroText("TikTok import", color: LaterrrPalette.inkSecondary)

                Text("Import a list.")
                    .font(LaterrrTypography.display(32))
                    .foregroundStyle(LaterrrPalette.ink)

                Text("Paste a TikTok URL and laterrr will turn it into swipeable place cards.")
                    .font(LaterrrTypography.body(.subheadline))
                    .foregroundStyle(LaterrrPalette.inkSecondary)

                VStack(spacing: 8) {
                    TextField(
                        "",
                        text: $urlString,
                        prompt: Text("https://vt.tiktok.com/…")
                            .font(LaterrrTypography.accent(17))
                            .foregroundStyle(LaterrrPalette.inkTertiary),
                        axis: .vertical
                    )
                    .font(LaterrrTypography.body(.subheadline))
                    .foregroundStyle(LaterrrPalette.ink)
                    .tint(LaterrrPalette.ink)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($isURLFieldFocused)

                    HairlineDivider()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(LaterrrTypography.headline(.footnote))
                        .foregroundStyle(LaterrrPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay {
                            Rectangle()
                                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                        }
                }

                HStack(spacing: 12) {
                    Button {
                        urlString = TikTokImportURLParser.clipboardCandidate(
                            from: UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                        )
                        errorMessage = nil
                    } label: {
                        Text("Paste")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.inkOutline)

                    Button {
                        if let errorMessage = importAction(urlString) {
                            self.errorMessage = errorMessage
                        } else {
                            dismiss()
                        }
                    } label: {
                        Text("Import for later")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.inkPrimary)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .onAppear {
            isURLFieldFocused = urlString.isEmpty
        }
    }
}

private struct CaptureReviewSheet: View {
    let reviewState: CaptureReviewState
    let settingsStore: SettingsStore
    let saveAction: (PlaceSuggestion) -> Void
    let openAction: (PlaceSuggestion) -> Void

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    imageHero

                    InkCard {
                        MicroText("Best match", color: LaterrrPalette.inkSecondary)

                        Text(reviewState.analysis.narrative)
                            .font(LaterrrTypography.body(.subheadline))
                            .foregroundStyle(LaterrrPalette.inkSecondary)

                        if !reviewState.analysis.extractedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                MicroText("Read from the photo", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)

                                FlowLayout(reviewState.analysis.extractedText)
                            }
                        }
                    }

                    if reviewState.analysis.suggestions.isEmpty {
                        EmptyStateView(
                            title: "No confident match yet",
                            message: "Try a clearer storefront shot, enable location, or import another image with more visible signage.",
                            systemImage: "magnifyingglass.circle"
                        )
                    } else {
                        ForEach(reviewState.analysis.suggestions) { suggestion in
                            InkCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(suggestion.name)
                                                .font(LaterrrTypography.display(26))
                                                .foregroundStyle(LaterrrPalette.ink)

                                            Text(suggestion.shortAddress)
                                                .font(LaterrrTypography.body(.subheadline))
                                                .foregroundStyle(LaterrrPalette.inkSecondary)
                                        }

                                        Spacer()

                                        ConfidencePill(score: suggestion.score, caption: "SIGN MATCH")
                                    }

                                    MicroText(
                                        suggestionMetadata(for: suggestion),
                                        size: 9,
                                        kerning: 1.5,
                                        color: LaterrrPalette.inkSecondary
                                    )

                                    Text(suggestion.rationale)
                                        .font(LaterrrTypography.accent(17))
                                        .foregroundStyle(LaterrrPalette.inkSecondary)

                                    LookAroundSection(preview: suggestion.lookAroundPreview)

                                    HStack(spacing: 12) {
                                        Button {
                                            saveAction(suggestion)
                                        } label: {
                                            Text("Save")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.inkPrimary)

                                        Button {
                                            openAction(suggestion)
                                        } label: {
                                            Text("Maps")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.inkOutline)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func suggestionMetadata(for suggestion: PlaceSuggestion) -> String {
        var parts = [suggestion.category]

        if suggestion.distanceMeters > 0 {
            parts.append("\(Int(suggestion.distanceMeters.rounded())) m away")
        }

        return parts.joined(separator: " · ")
    }

    private var imageHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: reviewState.photo.image)
                .resizable()
                .scaledToFill()
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                MicroText(reviewState.analysis.analysisMethod, size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)

                Text("Pick the right venue if the photo frame caught more than one place.")
                    .font(LaterrrTypography.body(.footnote))
                    .foregroundStyle(LaterrrPalette.ink)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                HairlineDivider()
            }
        }
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }
}

private struct LookAroundSection: View {
    let preview: LookAroundPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                MicroText("Look Around", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)

                Spacer()

                if let verificationScore = preview.verificationScore {
                    ConfidencePill(score: verificationScore, caption: "ALIGNED")
                } else {
                    LaterrrTag(title: preview.availability.title)
                }
            }

            if let snapshotData = preview.snapshotData, let image = UIImage(data: snapshotData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
            } else {
                CrosshatchPlaceholder(
                    caption: preview.availability == .disabled ? "Look Around off" : "Not available here"
                )
                .frame(height: 120)
            }

            Text(preview.summary)
                .font(LaterrrTypography.body(.footnote))
                .foregroundStyle(LaterrrPalette.inkSecondary)

            if !preview.matchedTokens.isEmpty {
                FlowLayout(preview.matchedTokens)
            }
        }
        .padding(14)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }
}

private struct FlowLayout: View {
    let items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    LaterrrTag(title: item)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .foregroundStyle(LaterrrPalette.ink)
                }
            }
        }
    }
}
