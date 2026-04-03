import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CaptureViewModel()
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pinchBaseZoomFactor: CGFloat?

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
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
        } else {
            VStack(spacing: 20) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 62, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.accent)

                Text("Point at the storefront")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Text("Take a clean venue shot and Laterrr checks the sign text against places nearby.")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(LaterrrPalette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                if viewModel.cameraSession.authorizationStatus != .authorized {
                    Text("Camera permission is off right now. You can still import a photo from your library below.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(LaterrrPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }
            .padding(24)
        }
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

            Circle()
                .fill(Color.clear)
                .frame(width: 56, height: 56)
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
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(LaterrrPalette.textPrimary)

                    Text(settingsStore.enableLookAroundVerification
                         ? "Laterrr is reading the sign, checking nearby places, and verifying strong candidates with Look Around where available."
                         : "Laterrr is reading the sign, checking nearby places, and trimming anything that looks too far away.")
                        .font(.system(.body, design: .rounded))
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
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text(reviewState.analysis.narrative)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        if !reviewState.analysis.extractedText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Read from the photo")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
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
                                                .font(.system(.title3, design: .rounded, weight: .bold))
                                                .foregroundStyle(LaterrrPalette.textPrimary)

                                            Text(suggestion.shortAddress)
                                                .font(.system(.body, design: .rounded))
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
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(LaterrrPalette.textSecondary)

                                    Text(suggestion.rationale)
                                        .font(.system(.subheadline, design: .rounded))
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
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(LaterrrPalette.textPrimary)

                    Text("Pick the right venue if the photo frame caught more than one place.")
                        .font(.system(.headline, design: .rounded))
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
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(LaterrrPalette.textPrimary)

                Spacer()

                if let verificationScore = preview.verificationScore {
                    Text("\(Int((verificationScore * 100).rounded()))%")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(LaterrrPalette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(LaterrrPalette.accentSoft.opacity(0.72))
                        )
                } else {
                    Text(preview.availability.title)
                        .font(.system(.caption, design: .rounded, weight: .bold))
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
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(LaterrrPalette.textPrimary)
                        }
                    }
            }

            Text(preview.summary)
                .font(.system(.footnote, design: .rounded))
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
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
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
