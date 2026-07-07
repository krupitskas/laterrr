import CoreLocation
import ImageIO
import Photos
import SwiftData
import SwiftUI

struct PhotoLibraryReviewCandidate: Identifiable {
    let id: String
    let photoData: Data
    let capturedAt: Date
    let location: CLLocation?
    let analysis: CaptureAnalysisPayload
}

struct PhotoLibraryReviewDeck {
    let dayWindow: Int
    let candidates: [PhotoLibraryReviewCandidate]
}

enum PhotoLibraryReviewError: LocalizedError {
    case unauthorized
    case noRecentPhotos
    case noPlacePhotos
    case photoUnavailable
    case noMatchForPhoto

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "laterrr needs Photos access to review your recent place shots."
        case .noRecentPhotos:
            return "laterrr could not find recent photos in that date range with location data."
        case .noPlacePhotos:
            return "laterrr checked your recent photos, but it did not find believable cafe, restaurant, or storefront shots yet."
        case .photoUnavailable:
            return "laterrr could not load that photo from your library."
        case .noMatchForPhoto:
            return "laterrr could not match that photo to a place. Try one with clearer signage or location data."
        }
    }
}

@MainActor
final class PhotoLibraryReviewController: ObservableObject {
    @Published var isPreparing = false
    @Published var isScanning = false
    @Published var alertMessage: String?
    @Published private(set) var deck: PhotoLibraryReviewDeck?
    @Published private(set) var selectedSuggestionIndices: [String: Int] = [:]
    @Published private(set) var processedPhotoCount = 0
    @Published private(set) var totalPhotoCount = 0
    @Published private(set) var matchedPhotoCount = 0

    private var reviewTask: Task<Void, Never>?

    var isPresentingReview: Bool {
        deck != nil
    }

    var remainingCount: Int {
        deck?.candidates.count ?? 0
    }

    var progressFraction: Double {
        guard totalPhotoCount > 0 else { return 0 }
        return Double(processedPhotoCount) / Double(totalPhotoCount)
    }

    var progressTitle: String {
        if remainingCount > 0 {
            return "\(remainingCount) place\(remainingCount == 1 ? "" : "s") left to review"
        }

        if isScanning {
            return "Finding place photos..."
        }

        return "Review complete"
    }

    var progressSummary: String {
        guard totalPhotoCount > 0 else {
            return "Preparing recent photos..."
        }

        if isScanning {
            let readyCount = remainingCount
            return "\(processedPhotoCount) of \(totalPhotoCount) photos checked - \(readyCount) ready now"
        }

        return "Scan complete - \(matchedPhotoCount) place photo\(matchedPhotoCount == 1 ? "" : "s") found"
    }

    var currentCandidate: PhotoLibraryReviewCandidate? {
        deck?.candidates.first
    }

    var currentSuggestion: PlaceSuggestion? {
        guard let candidate = currentCandidate else { return nil }
        let suggestionIndex = selectedSuggestionIndices[candidate.id] ?? 0
        guard candidate.analysis.suggestions.indices.contains(suggestionIndex) else {
            return candidate.analysis.suggestions.first
        }
        return candidate.analysis.suggestions[suggestionIndex]
    }

    func startReview(dayWindow: Int, enableLookAroundVerification: Bool) {
        reviewTask?.cancel()
        resetSession(preserveAlert: false)
        isPreparing = true

        reviewTask = Task { [weak self] in
            guard let self else { return }

            do {
                let assets = try await PhotoLibraryReviewService.prepareAssets(dayWindow: dayWindow)

                totalPhotoCount = assets.count
                deck = PhotoLibraryReviewDeck(dayWindow: dayWindow, candidates: [])
                isPreparing = false
                isScanning = true

                for asset in assets {
                    guard !Task.isCancelled else { return }

                    if let candidate = await PhotoLibraryReviewService.candidate(
                        for: asset,
                        enableLookAroundVerification: enableLookAroundVerification
                    ) {
                        append(candidate, dayWindow: dayWindow)
                    }

                    guard !Task.isCancelled else { return }
                    processedPhotoCount += 1
                }

                isScanning = false
                reviewTask = nil

                if matchedPhotoCount == 0 {
                    let noPlaceMessage = PhotoLibraryReviewError.noPlacePhotos.localizedDescription
                    resetSession(preserveAlert: true)
                    alertMessage = noPlaceMessage
                    return
                }

                finishIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }

                let errorMessage = error.localizedDescription
                reviewTask = nil
                resetSession(preserveAlert: true)
                alertMessage = errorMessage
            }
        }
    }

    // Reviews one deliberately-picked photo: same deck UI as the bulk scan,
    // but the scene filters are skipped — the user already chose the photo.
    func startSinglePhotoReview(itemIdentifier: String?, enableLookAroundVerification: Bool) {
        guard let itemIdentifier, !itemIdentifier.isEmpty else {
            alertMessage = PhotoLibraryReviewError.photoUnavailable.localizedDescription
            return
        }

        reviewTask?.cancel()
        resetSession(preserveAlert: false)
        isPreparing = true

        reviewTask = Task { [weak self] in
            guard let self else { return }

            do {
                let candidate = try await PhotoLibraryReviewService.singlePhotoCandidate(
                    itemIdentifier: itemIdentifier,
                    enableLookAroundVerification: enableLookAroundVerification
                )

                guard !Task.isCancelled else { return }

                totalPhotoCount = 1
                processedPhotoCount = 1
                isPreparing = false
                isScanning = false
                deck = PhotoLibraryReviewDeck(dayWindow: 0, candidates: [])
                append(candidate, dayWindow: 0)
                reviewTask = nil
            } catch {
                guard !Task.isCancelled else { return }

                let errorMessage = error.localizedDescription
                reviewTask = nil
                resetSession(preserveAlert: true)
                alertMessage = errorMessage
            }
        }
    }

    func selectSuggestion(index: Int) {
        guard let candidate = currentCandidate else { return }
        guard candidate.analysis.suggestions.indices.contains(index) else { return }
        selectedSuggestionIndices[candidate.id] = index
    }

    func skipCurrent() {
        removeCurrentCandidate()
    }

    func saveCurrent(modelContext: ModelContext) {
        guard
            let candidate = currentCandidate,
            let suggestion = currentSuggestion
        else {
            return
        }

        let matchedText = candidate.analysis.extractedText.joined(separator: ", ")
        let reviewedDate = candidate.capturedAt.formatted(date: .abbreviated, time: .shortened)

        _ = SavedPlaceStore.save(
            SavedPlaceDraft(
                name: suggestion.name,
                shortAddress: suggestion.shortAddress,
                fullAddress: suggestion.fullAddress,
                category: suggestion.category,
                latitude: suggestion.latitude,
                longitude: suggestion.longitude,
                createdAt: candidate.capturedAt,
                confidence: suggestion.score,
                matchedText: matchedText,
                selectionReason: "Reviewed from Photos on \(reviewedDate) and confirmed in laterrr.",
                analysisMode: "\(candidate.analysis.analysisMethod) + Photos review",
                source: .photoLibrary,
                websiteURLString: suggestion.websiteURL?.absoluteString,
                cuisineTags: candidate.analysis.cuisineTags,
                photoData: candidate.photoData
            ),
            in: modelContext
        )

        removeCurrentCandidate()
    }

    func stopScanning() {
        guard isScanning else { return }

        reviewTask?.cancel()
        reviewTask = nil
        isScanning = false

        if deck?.candidates.isEmpty ?? true {
            resetSession(preserveAlert: false)
        }
    }

    func dismissReview() {
        reviewTask?.cancel()
        reviewTask = nil
        resetSession(preserveAlert: true)
    }

    func dismissAlert() {
        alertMessage = nil
    }

    private func append(_ candidate: PhotoLibraryReviewCandidate, dayWindow: Int) {
        let currentCandidates = deck?.candidates ?? []
        let updatedCandidates = currentCandidates + [candidate]

        selectedSuggestionIndices[candidate.id] = 0
        matchedPhotoCount += 1
        deck = PhotoLibraryReviewDeck(dayWindow: dayWindow, candidates: updatedCandidates)
    }

    private func removeCurrentCandidate() {
        guard let deck else { return }
        guard let currentCandidate else {
            finishIfNeeded()
            return
        }

        let updatedCandidates = Array(deck.candidates.dropFirst())
        selectedSuggestionIndices[currentCandidate.id] = nil
        self.deck = PhotoLibraryReviewDeck(dayWindow: deck.dayWindow, candidates: updatedCandidates)
        finishIfNeeded()
    }

    private func finishIfNeeded() {
        guard let deck else { return }
        guard deck.candidates.isEmpty else { return }
        guard !isScanning else { return }

        resetSession(preserveAlert: true)
    }

    private func resetSession(preserveAlert: Bool) {
        isPreparing = false
        isScanning = false
        deck = nil
        selectedSuggestionIndices = [:]
        processedPhotoCount = 0
        totalPhotoCount = 0
        matchedPhotoCount = 0

        if !preserveAlert {
            alertMessage = nil
        }
    }
}

enum PhotoLibraryReviewService {
    private static let targetImageSize = CGSize(width: 1800, height: 1800)

    static func prepareAssets(dayWindow: Int) async throws -> [PHAsset] {
        let authorizationStatus = await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryReviewError.unauthorized
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -dayWindow, to: .now) ?? .now
        let assets = fetchAssets(since: cutoffDate)

        guard !assets.isEmpty else {
            throw PhotoLibraryReviewError.noRecentPhotos
        }

        return assets
    }

    static func singlePhotoCandidate(
        itemIdentifier: String,
        enableLookAroundVerification: Bool
    ) async throws -> PhotoLibraryReviewCandidate {
        let authorizationStatus = await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryReviewError.unauthorized
        }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [itemIdentifier], options: nil)
        guard let asset = fetchResult.firstObject else {
            throw PhotoLibraryReviewError.photoUnavailable
        }

        guard let photoData = await photoData(for: asset) else {
            throw PhotoLibraryReviewError.photoUnavailable
        }

        let extractedText = await VenueTextRecognizer.recognizeText(in: photoData)
        let analysis = await PlaceCapturePipeline.analyze(
            photoData: photoData,
            location: asset.location,
            enableLookAroundVerification: enableLookAroundVerification,
            extractedText: extractedText
        )

        guard !analysis.suggestions.isEmpty else {
            throw PhotoLibraryReviewError.noMatchForPhoto
        }

        return PhotoLibraryReviewCandidate(
            id: asset.localIdentifier,
            photoData: photoData,
            capturedAt: asset.creationDate ?? .now,
            location: asset.location,
            analysis: analysis
        )
    }

    static func candidate(
        for asset: PHAsset,
        enableLookAroundVerification: Bool
    ) async -> PhotoLibraryReviewCandidate? {
        guard !asset.mediaSubtypes.contains(.photoScreenshot) else { return nil }
        guard let location = asset.location else { return nil }
        guard let capturedAt = asset.creationDate else { return nil }
        guard let photoData = await photoData(for: asset) else { return nil }

        let exteriorAssessment = await FoodVenueExteriorClassifier.assess(photoData: photoData)
        guard PhotoPlaceFilter.shouldInspect(exteriorAssessment: exteriorAssessment) else {
            return nil
        }

        let humanAssessment = await ForegroundHumanDetector.assess(photoData: photoData)
        guard PhotoPlaceFilter.shouldInspect(
            exteriorAssessment: exteriorAssessment,
            humanAssessment: humanAssessment
        ) else {
            return nil
        }

        let extractedText = await VenueTextRecognizer.recognizeText(in: photoData)
        let sceneAssessment = PhotoPlaceFilter.assess(
            extractedText: extractedText,
            exteriorAssessment: exteriorAssessment,
            humanAssessment: humanAssessment
        )

        guard sceneAssessment.shouldAnalyze else { return nil }

        let analysis = await PlaceCapturePipeline.analyze(
            photoData: photoData,
            location: location,
            enableLookAroundVerification: enableLookAroundVerification,
            extractedText: extractedText
        )

        guard isWorthReviewing(analysis: analysis, sceneAssessment: sceneAssessment) else {
            return nil
        }

        return PhotoLibraryReviewCandidate(
            id: asset.localIdentifier,
            photoData: photoData,
            capturedAt: capturedAt,
            location: location,
            analysis: analysis
        )
    }

    private static func isWorthReviewing(
        analysis: CaptureAnalysisPayload,
        sceneAssessment: PhotoSceneAssessment
    ) -> Bool {
        guard let topSuggestion = analysis.suggestions.first else {
            return false
        }

        guard isFoodVenueCategory(topSuggestion.category) else {
            return false
        }

        if !topSuggestion.matchedTokens.isEmpty {
            if sceneAssessment.isLikelyFoodPlaceScene {
                return topSuggestion.distanceMeters <= 220 && topSuggestion.score >= 0.42
            }

            return sceneAssessment.isLikelyPlaceScene
                && topSuggestion.distanceMeters <= 140
                && topSuggestion.score >= 0.54
        }

        guard sceneAssessment.isLikelyFoodPlaceScene else {
            return false
        }

        if analysis.extractedText.isEmpty {
            return topSuggestion.distanceMeters <= 90 && topSuggestion.score >= 0.60
        }

        return topSuggestion.distanceMeters <= 120 && topSuggestion.score >= 0.56
    }

    private static func isFoodVenueCategory(_ category: String) -> Bool {
        let lowered = category.lowercased()
        return lowered.contains("cafe")
            || lowered.contains("coffee")
            || lowered.contains("restaurant")
            || lowered.contains("bakery")
            || lowered.contains("brewery")
            || lowered.contains("food")
    }

    private static func requestAuthorizationIfNeeded() async -> PHAuthorizationStatus {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .notDetermined else {
            return currentStatus
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func fetchAssets(since cutoffDate: Date) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@",
            PHAssetMediaType.image.rawValue,
            cutoffDate as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    private static func photoData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            options.version = .current

            var hasResumed = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetImageSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !hasResumed else { return }

                if (info?[PHImageCancelledKey] as? Bool) == true {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }

                if info?[PHImageErrorKey] as? Error != nil {
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }

                if (info?[PHImageResultIsDegradedKey] as? Bool) == true {
                    return
                }

                hasResumed = true

                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: image.jpegData(compressionQuality: 0.9))
            }
        }
    }
}

private struct PhotoSceneAssessment {
    let shouldAnalyze: Bool
    let isLikelyPlaceScene: Bool
    let isLikelyFoodPlaceScene: Bool
}

private enum PhotoPlaceFilter {
    private static let venueStopWords: Set<String> = [
        "open", "welcome", "hello", "please", "thanks", "thank", "today", "daily", "fresh",
        "cafe", "restaurant", "coffee", "bar", "bistro"
    ]

    private static let rejectedTextKeywords: Set<String> = [
        "menu", "receipt", "subtotal", "total", "tip", "tva", "tax", "payment", "cash",
        "visa", "mastercard", "bill", "invoice", "amount", "server", "table", "change",
        "merci", "items", "order", "wc", "toilet", "restroom", "lavatory", "office",
        "meeting", "sortie", "exit"
    ]

    private static let foodTextKeywords: Set<String> = [
        "bakery", "bar", "bistro", "boulangerie", "brasserie", "brunch", "cafe", "cafeteria",
        "cantine", "coffee", "crepe", "creperie", "croissant", "diner", "espresso", "gelato",
        "patisserie", "pizza", "pizzeria", "pub", "ramen", "restaurant", "sushi", "tea"
    ]

    private static let foodSceneIdentifiers: Set<String> = [
        "bakery",
        "bakery_exterior",
        "bistro_exterior",
        "brasserie_exterior",
        "cafe_exterior",
        "cafe_exterior_sign",
        "cafe_storefront",
        "cafeteria",
        "coffee",
        "coffee_bean",
        "coffee_shop_exterior",
        "restaurant",
        "restaurant_exterior",
        "restaurant_exterior_sign",
        "restaurant_storefront"
    ]

    private static let foodSceneKeywords: [String] = [
        "restaurant", "coffee", "bakery", "bistro", "cafe", "sign", "terrace", "patio"
    ]

    private static let placeContextIdentifiers: Set<String> = [
        "awning_storefront",
        "building",
        "building_facade",
        "shop_exterior",
        "shop_entrance",
        "storefront_exterior",
        "storefront_signage",
        "street",
        "street_sign",
        "urban_streetfront"
    ]

    private static let placeContextKeywords: [String] = [
        "building", "architecture", "street", "city", "urban", "road", "sidewalk",
        "plaza", "square", "store", "shop", "market", "facade", "sign", "entrance", "front"
    ]

    private static let negativeSceneIdentifiers: Set<String> = [
        "bathroom_sign",
        "cat",
        "dog",
        "dog_indoors",
        "drink_closeup",
        "food_closeup",
        "home_interior",
        "living_room_couch",
        "people_dining_indoors",
        "person_at_restaurant_table",
        "menu_closeup",
        "office_sign",
        "painting",
        "receipt",
        "restaurant_interior",
        "selfie_in_cafe",
        "sofa",
        "toilet_seat",
        "toilet_sign"
    ]

    private static let negativeSceneKeywords: [String] = [
        "dog", "cat", "pet", "couch", "sofa", "bed", "bedroom", "blanket", "painting",
        "artwork", "menu", "receipt", "invoice", "food", "plate", "dish", "dessert",
        "drink", "cocktail", "wine", "beer", "living room", "toilet", "interior",
        "portrait", "people", "selfie", "table"
    ]

    static func shouldInspect(exteriorAssessment: FoodVenueExteriorAssessment) -> Bool {
        if exteriorAssessment.negativeConfidence >= 0.30,
           exteriorAssessment.positiveConfidence < 0.18,
           !exteriorAssessment.isLikelyExteriorContext {
            return false
        }

        if exteriorAssessment.isLikelyExteriorVenue && exteriorAssessment.contextConfidence >= 0.15 {
            return true
        }

        if exteriorAssessment.isLikelyExteriorContext && exteriorAssessment.negativeConfidence < 0.34 {
            return true
        }

        return (
            exteriorAssessment.contextConfidence >= 0.16
                || exteriorAssessment.positiveConfidence >= 0.22
        )
            && exteriorAssessment.negativeConfidence < 0.34
    }

    static func shouldInspect(
        exteriorAssessment: FoodVenueExteriorAssessment,
        humanAssessment: ForegroundHumanAssessment
    ) -> Bool {
        if humanAssessment.hasDominantForegroundPerson,
           exteriorAssessment.contextConfidence < 0.14,
           exteriorAssessment.positiveConfidence < 0.22 {
            return false
        }

        if humanAssessment.centeredFaceArea >= 0.028,
           exteriorAssessment.contextConfidence < 0.16,
           exteriorAssessment.positiveConfidence < 0.24 {
            return false
        }

        return true
    }

    static func assess(
        extractedText: [String],
        exteriorAssessment: FoodVenueExteriorAssessment,
        humanAssessment: ForegroundHumanAssessment
    ) -> PhotoSceneAssessment {
        performAssessment(
            extractedText: extractedText,
            exteriorAssessment: exteriorAssessment,
            humanAssessment: humanAssessment
        )
    }

    private static func performAssessment(
        extractedText: [String],
        exteriorAssessment: FoodVenueExteriorAssessment,
        humanAssessment: ForegroundHumanAssessment
    ) -> PhotoSceneAssessment {
        let normalizedText = extractedText.map { $0.lowercased() }
        let rejectedTextHits = normalizedText.filter { rejectedTextKeywords.contains($0) }

        if !rejectedTextHits.isEmpty {
            return PhotoSceneAssessment(
                shouldAnalyze: false,
                isLikelyPlaceScene: false,
                isLikelyFoodPlaceScene: false
            )
        }

        let strongVenueTextCount = normalizedText.filter { token in
            token.count >= 4
                && !rejectedTextKeywords.contains(token)
                && !venueStopWords.contains(token)
        }.count
        let foodTextHitCount = normalizedText.filter { foodTextKeywords.contains($0) }.count

        let sceneLabels = exteriorAssessment.labels
        let foodScore = max(
            exteriorAssessment.positiveConfidence,
            score(
                for: sceneLabels,
                matchingIdentifiers: foodSceneIdentifiers,
                matchingKeywords: foodSceneKeywords
            )
        )
        let placeScore = max(
            exteriorAssessment.contextConfidence,
            score(
                for: sceneLabels,
                matchingIdentifiers: placeContextIdentifiers,
                matchingKeywords: placeContextKeywords
            )
        )
        let negativeScore = max(
            exteriorAssessment.negativeConfidence,
            score(
                for: sceneLabels,
                matchingIdentifiers: negativeSceneIdentifiers,
                matchingKeywords: negativeSceneKeywords
            )
        )

        let isLikelyFoodPlaceScene = exteriorAssessment.isLikelyExteriorVenue
            || (foodScore >= 0.22 && placeScore >= 0.16 && negativeScore < 0.28)
            || (foodTextHitCount >= 1 && placeScore >= 0.17 && negativeScore < 0.30)
        let isLikelyPlaceScene = isLikelyFoodPlaceScene
            || exteriorAssessment.isLikelyExteriorContext
            || (placeScore >= 0.16 && negativeScore < 0.34)

        if humanAssessment.hasDominantForegroundPerson,
           placeScore < 0.16,
           foodTextHitCount == 0,
           strongVenueTextCount == 0 {
            return PhotoSceneAssessment(
                shouldAnalyze: false,
                isLikelyPlaceScene: false,
                isLikelyFoodPlaceScene: false
            )
        }

        if negativeScore >= 0.36, !isLikelyPlaceScene, foodTextHitCount == 0, strongVenueTextCount == 0 {
            return PhotoSceneAssessment(
                shouldAnalyze: false,
                isLikelyPlaceScene: false,
                isLikelyFoodPlaceScene: false
            )
        }

        let shouldAnalyze = isLikelyFoodPlaceScene
            || (isLikelyPlaceScene && negativeScore < 0.34)
            || (foodTextHitCount >= 1 && isLikelyPlaceScene)
            || (
                strongVenueTextCount >= 1
                    && placeScore >= 0.14
                    && negativeScore < 0.34
            )

        return PhotoSceneAssessment(
            shouldAnalyze: shouldAnalyze,
            isLikelyPlaceScene: isLikelyPlaceScene,
            isLikelyFoodPlaceScene: isLikelyFoodPlaceScene
        )
    }

    private static func score(
        for labels: [FoodVenueExteriorLabel],
        matchingIdentifiers identifiers: Set<String>,
        matchingKeywords keywords: [String]
    ) -> Double {
        labels
            .filter { label in
                identifiers.contains(label.identifier)
                    || keywords.contains { keyword in
                        label.identifier.contains(keyword)
                    }
            }
            .map(\.confidence)
            .reduce(0, +)
    }
}
