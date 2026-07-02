import Combine
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CaptureReviewState: Identifiable {
    let id = UUID()
    let photo: CapturedPhoto
    let analysis: CaptureAnalysisPayload
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var isAnalyzing = false
    @Published var alertMessage: String?
    @Published var reviewState: CaptureReviewState?
    @Published var bannerMessage: String?

    let cameraSession = CameraSessionModel()
    let locationStore = LocationStore()

    private var cancellables = Set<AnyCancellable>()
    private var bannerTask: Task<Void, Never>?

    init() {
        cameraSession.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        locationStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func onAppear() {
        locationStore.requestAuthorizationIfNeeded()
        cameraSession.prepare()
    }

    // The camera session intentionally keeps running across tab switches so
    // returning to Capture is instant; the system pauses it in the background.
    func onDisappear() {
        clearBanner()
    }

    func capture(enableLookAroundVerification: Bool) {
        Task {
            do {
                let photo = try await cameraSession.capturePhoto()
                await analyze(
                    photo: photo,
                    enableLookAroundVerification: enableLookAroundVerification
                )
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func importPhoto(from item: PhotosPickerItem?, enableLookAroundVerification: Bool) {
        guard let item else { return }

        Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                alertMessage = "laterrr could not import that image."
                return
            }

            let photo = CapturedPhoto(image: image, data: data)
            await analyze(
                photo: photo,
                enableLookAroundVerification: enableLookAroundVerification
            )
        }
    }

    func save(
        suggestion: PlaceSuggestion,
        settings: SettingsStore,
        modelContext: ModelContext
    ) {
        guard let currentReviewState = reviewState else { return }

        let outcome = SavedPlaceStore.save(
            SavedPlaceDraft(
                name: suggestion.name,
                shortAddress: suggestion.shortAddress,
                fullAddress: suggestion.fullAddress,
                category: suggestion.category,
                latitude: suggestion.latitude,
                longitude: suggestion.longitude,
                createdAt: .now,
                confidence: suggestion.score,
                matchedText: currentReviewState.analysis.extractedText.joined(separator: ", "),
                selectionReason: suggestion.rationale,
                analysisMode: currentReviewState.analysis.analysisMethod,
                source: .camera,
                websiteURLString: suggestion.websiteURL?.absoluteString,
                photoData: settings.keepPhotoSnapshot ? currentReviewState.photo.data : nil
            ),
            in: modelContext
        )

        let place = outcome.place

        showBanner(
            outcome.wasInserted
                ? "Saved \(place.name) to laterrr."
                : "\(place.name) was already in laterrr, so I refreshed its details."
        )

        reviewState = nil
    }

    func showBanner(_ message: String, autoDismissAfter delay: Duration? = .seconds(2.6)) {
        bannerTask?.cancel()
        bannerMessage = message

        guard let delay else {
            return
        }

        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.bannerMessage = nil
            }
        }
    }

    func clearBanner() {
        bannerTask?.cancel()
        bannerMessage = nil
    }

    private func analyze(photo: CapturedPhoto, enableLookAroundVerification: Bool) async {
        isAnalyzing = true
        clearBanner()

        let analysis = await PlaceCapturePipeline.analyze(
            photoData: photo.data,
            location: locationStore.currentLocation,
            enableLookAroundVerification: enableLookAroundVerification
        )

        reviewState = CaptureReviewState(photo: photo, analysis: analysis)
        isAnalyzing = false
    }
}
