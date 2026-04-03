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
                .overlay(alignment: .bottom) {
                    captureControls
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                }

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
                Text(bannerMessage)
                    .font(LaterrrTypography.caption(.subheadline))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(
                        Glass.regular.tint(LaterrrPalette.accentSoft.opacity(0.72)),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.76), lineWidth: 1)
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
            LaterrrLoadingView(
                title: "loading camera",
                message: "laterrr is warming up the camera so you can capture the place in one shot."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 20) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.accent)

                Text("Point at the storefront")
                    .font(LaterrrTypography.display(36))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text("Take a clean venue shot and laterrr checks the sign text against places nearby.")
                    .font(LaterrrTypography.body(.title3))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if viewModel.cameraSession.authorizationStatus != .authorized {
                    Text("Camera permission is off right now. You can still import a photo from your library below.")
                        .font(LaterrrTypography.body())
                        .foregroundStyle(LaterrrPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(24)
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
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .frame(width: 56, height: 56)
                    .glassEffect(
                        Glass.regular.tint(Color.white.opacity(0.68)),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                    }
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
                        .strokeBorder(Color.white.opacity(0.92), lineWidth: 6)
                        .frame(width: 82, height: 82)

                    Circle()
                        .fill(Color.white.opacity(0.98))
                        .frame(width: 64, height: 64)
                }
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.cameraSession.authorizationStatus != .authorized)

            Spacer()

            Button {
                pastedTikTokURLString = TikTokImportURLParser.clipboardCandidate(
                    from: UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                )
                isTikTokPasteSheetPresented = true
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textPrimary)
                    .frame(width: 56, height: 56)
                    .glassEffect(
                        Glass.regular.tint(Color.white.opacity(0.68)),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(
            Glass.regular.tint(Color.white.opacity(0.34)),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
        }
    }

    private var analyzingOverlay: some View {
        Color.black.opacity(0.10)
            .ignoresSafeArea()
            .overlay {
                GlassCard(alignment: .center) {
                    ProgressView()
                        .tint(LaterrrPalette.accent)
                        .scaleEffect(1.2)

                    Text("Finding the best nearby match")
                        .font(LaterrrTypography.headline())
                        .foregroundStyle(LaterrrPalette.textPrimary)

                    Text(settingsStore.enableLookAroundVerification
                         ? "laterrr is reading the sign, checking nearby places, and verifying strong candidates with Look Around where available."
                         : "laterrr is reading the sign, checking nearby places, and trimming anything that looks too far away.")
                        .font(LaterrrTypography.body())
                        .foregroundStyle(LaterrrPalette.textSecondary)
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

            VStack(alignment: .leading, spacing: 18) {
                Text("Import TikTok list")
                    .font(LaterrrTypography.display(30))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text("Paste a TikTok URL and laterrr will turn it into swipeable place cards.")
                    .font(LaterrrTypography.body())
                    .foregroundStyle(LaterrrPalette.textSecondary)

                TextField("https://vt.tiktok.com/...", text: $urlString, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .focused($isURLFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(.red.opacity(0.88))
                }

                HStack(spacing: 12) {
                    Button {
                        urlString = TikTokImportURLParser.clipboardCandidate(
                            from: UIPasteboard.general.string ?? UIPasteboard.general.url?.absoluteString
                        )
                        errorMessage = nil
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)

                    Button {
                        if let errorMessage = importAction(urlString) {
                            self.errorMessage = errorMessage
                        } else {
                            dismiss()
                        }
                    } label: {
                        Label("Import for later!", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
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

                    GlassCard {
                        Text("Best match")
                            .font(LaterrrTypography.display(28))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text(reviewState.analysis.narrative)
                            .font(LaterrrTypography.body())
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        if !reviewState.analysis.extractedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Read from the photo")
                                    .font(LaterrrTypography.caption(.subheadline))
                                    .foregroundStyle(LaterrrPalette.textSecondary)

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
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(suggestion.name)
                                                .font(LaterrrTypography.display(26))
                                                .foregroundStyle(LaterrrPalette.textPrimary)

                                            Text(suggestion.shortAddress)
                                                .font(LaterrrTypography.body())
                                                .foregroundStyle(LaterrrPalette.textSecondary)
                                        }

                                        Spacer()

                                        ConfidencePill(score: suggestion.score)
                                    }

                                    HStack(spacing: 10) {
                                        Label(suggestion.category, systemImage: "fork.knife")
                                        if suggestion.distanceMeters > 0 {
                                            Label("\(Int(suggestion.distanceMeters.rounded())) m", systemImage: "figure.walk")
                                        }
                                    }
                                    .font(LaterrrTypography.caption())
                                    .foregroundStyle(LaterrrPalette.textSecondary)

                                    Text(suggestion.rationale)
                                        .font(LaterrrTypography.body(.subheadline))
                                        .foregroundStyle(LaterrrPalette.textSecondary)

                                    LookAroundSection(preview: suggestion.lookAroundPreview)

                                    HStack(spacing: 12) {
                                        Button {
                                            saveAction(suggestion)
                                        } label: {
                                            Label("Save", systemImage: "bookmark.fill")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.glassProminent)

                                        Button {
                                            openAction(suggestion)
                                        } label: {
                                            Label("Apple Maps", systemImage: "map")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.glass)
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

    private var imageHero: some View {
        Image(uiImage: reviewState.photo.image)
            .resizable()
            .scaledToFill()
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(reviewState.analysis.analysisMethod)
                        .font(LaterrrTypography.caption())
                        .foregroundStyle(LaterrrPalette.textPrimary)

                    Text("Pick the right venue if the photo frame caught more than one place.")
                        .font(LaterrrTypography.headline())
                        .foregroundStyle(LaterrrPalette.textPrimary)
                }
                .padding(18)
                .glassEffect(
                    Glass.regular.tint(Color.white.opacity(0.70)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.78), lineWidth: 1)
                }
                .padding(16)
            }
    }
}

private struct LookAroundSection: View {
    let preview: LookAroundPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Look Around", systemImage: "binoculars")
                    .font(LaterrrTypography.caption(.subheadline))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Spacer()

                if let verificationScore = preview.verificationScore {
                    Text("\(Int((verificationScore * 100).rounded()))%")
                        .font(LaterrrTypography.caption())
                        .foregroundStyle(LaterrrPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LaterrrPalette.accentSoft.opacity(0.72))
                        )
                } else {
                    Text(preview.availability.title)
                        .font(LaterrrTypography.caption())
                        .foregroundStyle(LaterrrPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.52))
                        )
                }
            }

            if let snapshotData = preview.snapshotData, let image = UIImage(data: snapshotData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.34))
                    .frame(height: 120)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: preview.availability == .disabled ? "binoculars.slash" : "eye.slash")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(LaterrrPalette.textSecondary)

                            Text(preview.availability == .disabled ? "Look Around off" : "Not available here")
                                .font(LaterrrTypography.headline())
                                .foregroundStyle(LaterrrPalette.textPrimary)
                        }
                    }
            }

            Text(preview.summary)
                .font(LaterrrTypography.body(.footnote))
                .foregroundStyle(LaterrrPalette.textSecondary)

            if !preview.matchedTokens.isEmpty {
                FlowLayout(preview.matchedTokens)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
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

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .foregroundStyle(LaterrrPalette.textPrimary)
                }
            }
        }
    }
}
