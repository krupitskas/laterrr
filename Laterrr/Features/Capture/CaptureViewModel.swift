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

    func onDisappear() {
        cameraSession.stopRunning()
    }

    func capture() {
        Task {
            do {
                let photo = try await cameraSession.capturePhoto()
                await analyze(photo: photo)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func importPhoto(from item: PhotosPickerItem?) {
        guard let item else { return }

        Task {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                alertMessage = "Laterrr could not import that image."
                return
            }

            let photo = CapturedPhoto(image: image, data: data)
            await analyze(photo: photo)
        }
    }

    func save(
        suggestion: PlaceSuggestion,
        settings: SettingsStore,
        modelContext: ModelContext
    ) {
        guard let currentReviewState = reviewState else { return }

        let place = SavedPlace(
            name: suggestion.name,
            shortAddress: suggestion.shortAddress,
            fullAddress: suggestion.fullAddress,
            category: suggestion.category,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            confidence: suggestion.score,
            matchedText: currentReviewState.analysis.extractedText.joined(separator: ", "),
            selectionReason: suggestion.rationale,
            analysisMode: currentReviewState.analysis.analysisMethod,
            websiteURLString: suggestion.websiteURL?.absoluteString,
            photoData: settings.keepPhotoSnapshot ? currentReviewState.photo.data : nil
        )

        modelContext.insert(place)
        try? modelContext.save()

        bannerMessage = "Saved \(suggestion.name) to Laterrr."

        if settings.autoOpenMapAfterSave {
            MapsExporter.open(url: MapsExporter.url(for: suggestion, provider: settings.preferredMapsProvider))
        }

        reviewState = nil
    }

    private func analyze(photo: CapturedPhoto) async {
        isAnalyzing = true
        bannerMessage = nil

        let analysis = await PlaceCapturePipeline.analyze(
            photoData: photo.data,
            location: locationStore.currentLocation
        )

        reviewState = CaptureReviewState(photo: photo, analysis: analysis)
        isAnalyzing = false
    }
}
