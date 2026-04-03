import CoreML
import ImageIO
import Vision

struct FoodVenueExteriorLabel: Sendable {
    let identifier: String
    let confidence: Double
}

struct FoodVenueExteriorAssessment: Sendable {
    let isLikelyExteriorVenue: Bool
    let isLikelyExteriorContext: Bool
    let confidence: Double
    let positiveConfidence: Double
    let contextConfidence: Double
    let negativeConfidence: Double
    let labels: [FoodVenueExteriorLabel]
    let source: Source

    enum Source: String, Sendable {
        case mobileCLIP
        case customModel
        case builtInVision
    }
}

enum FoodVenueExteriorClassifier {
    private static let queue = DispatchQueue(label: "Laterrr.food.venue.exterior", qos: .userInitiated)
    private static let modelName = "FoodVenueExteriorClassifier"
    private static let positiveCustomLabels: Set<String> = [
        "bakery_exterior",
        "bar_exterior",
        "bistro_exterior",
        "brasserie_exterior",
        "building_exterior",
        "cafe_exterior",
        "coffee_shop_exterior",
        "food_venue_exterior",
        "restaurant_exterior"
    ]
    private static let contextCustomLabels: Set<String> = [
        "building_exterior",
        "facade",
        "shop_exterior",
        "shopfront",
        "storefront",
        "street_storefront"
    ]
    private static let negativeCustomLabels: Set<String> = [
        "artwork",
        "bathroom_sign",
        "home_interior",
        "menu",
        "office_interior",
        "office_sign",
        "painting",
        "pet",
        "receipt"
    ]
    private static let positiveVisionIdentifiers: Set<String> = [
        "bakery",
        "cafeteria",
        "coffee",
        "coffee_bean",
        "restaurant"
    ]
    private static let positiveVisionKeywords: [String] = [
        "bakery",
        "bistro",
        "brasserie",
        "cafe",
        "coffee",
        "restaurant"
    ]
    private static let contextVisionIdentifiers: Set<String> = [
        "building",
        "plaza",
        "road",
        "shop",
        "store",
        "street",
        "street_sign"
    ]
    private static let contextVisionKeywords: [String] = [
        "architecture",
        "building",
        "city",
        "facade",
        "market",
        "plaza",
        "road",
        "shop",
        "store",
        "street",
        "urban"
    ]
    private static let negativeVisionIdentifiers: Set<String> = [
        "cat",
        "dog",
        "painting",
        "receipt",
        "sofa",
        "toilet_seat"
    ]
    private static let negativeVisionKeywords: [String] = [
        "bathroom",
        "bed",
        "bedroom",
        "couch",
        "desk",
        "dog",
        "food",
        "menu",
        "painting",
        "pet",
        "receipt",
        "sign",
        "sofa",
        "toilet"
    ]

    nonisolated(unsafe) private static var cachedModel: VNCoreMLModel?
    nonisolated(unsafe) private static var attemptedModelLoad = false

    static func assess(photoData: Data) async -> FoodVenueExteriorAssessment {
        if let customAssessment = await withCheckedContinuation(
            { (continuation: CheckedContinuation<FoodVenueExteriorAssessment?, Never>) in
                queue.async {
                    continuation.resume(returning: customAssessment(photoData: photoData))
                }
            }
        ) {
            return customAssessment
        }

        if let mobileCLIPAssessment = await MobileCLIPVenueScorer.shared.assess(photoData: photoData) {
            return mobileCLIPAssessment
        }

        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: builtInAssessment(photoData: photoData))
            }
        }
    }

    private static func customAssessment(photoData: Data) -> FoodVenueExteriorAssessment? {
        if let customModel = customVisionModel(),
           let customLabels = classify(photoData: photoData, using: customModel),
           !customLabels.isEmpty {
            return evaluateCustom(labels: customLabels)
        }

        return nil
    }

    private static func builtInAssessment(photoData: Data) -> FoodVenueExteriorAssessment {
        let builtInLabels = classifyWithBuiltInVision(photoData: photoData)
        return evaluateBuiltIn(labels: builtInLabels)
    }

    private static func evaluateCustom(labels: [FoodVenueExteriorLabel]) -> FoodVenueExteriorAssessment {
        let positiveConfidence = maxLabelConfidence(
            in: labels,
            identifiers: positiveCustomLabels,
            keywords: Array(positiveCustomLabels)
        )
        let contextConfidence = maxLabelConfidence(
            in: labels,
            identifiers: contextCustomLabels,
            keywords: Array(contextCustomLabels)
        )
        let negativeConfidence = maxLabelConfidence(
            in: labels,
            identifiers: negativeCustomLabels,
            keywords: Array(negativeCustomLabels)
        )
        let confidence = max(
            0,
            positiveConfidence + (contextConfidence * 0.35) - (negativeConfidence * 0.80)
        )

        return FoodVenueExteriorAssessment(
            isLikelyExteriorVenue: positiveConfidence >= 0.45 && positiveConfidence >= negativeConfidence,
            isLikelyExteriorContext: contextConfidence >= 0.35 && contextConfidence >= negativeConfidence,
            confidence: confidence,
            positiveConfidence: positiveConfidence,
            contextConfidence: contextConfidence,
            negativeConfidence: negativeConfidence,
            labels: labels,
            source: .customModel
        )
    }

    private static func evaluateBuiltIn(labels: [FoodVenueExteriorLabel]) -> FoodVenueExteriorAssessment {
        let positiveConfidence = maxLabelConfidence(
            in: labels,
            identifiers: positiveVisionIdentifiers,
            keywords: positiveVisionKeywords
        )
        let contextConfidence = maxLabelConfidence(
            in: labels,
            identifiers: contextVisionIdentifiers,
            keywords: contextVisionKeywords
        )
        let negativeConfidence = maxLabelConfidence(
            in: labels,
            identifiers: negativeVisionIdentifiers,
            keywords: negativeVisionKeywords
        )
        let confidence = max(
            0,
            positiveConfidence + (contextConfidence * 0.25) - (negativeConfidence * 0.85)
        )

        return FoodVenueExteriorAssessment(
            isLikelyExteriorVenue: positiveConfidence >= 0.23
                && positiveConfidence >= (negativeConfidence + 0.04),
            isLikelyExteriorContext: contextConfidence >= 0.20
                && contextConfidence >= negativeConfidence,
            confidence: confidence,
            positiveConfidence: positiveConfidence,
            contextConfidence: contextConfidence,
            negativeConfidence: negativeConfidence,
            labels: labels,
            source: .builtInVision
        )
    }

    private static func customVisionModel() -> VNCoreMLModel? {
        if let cachedModel {
            return cachedModel
        }

        if attemptedModelLoad {
            return nil
        }

        attemptedModelLoad = true

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            return nil
        }

        guard let model = try? MLModel(contentsOf: modelURL) else {
            return nil
        }

        guard let visionModel = try? VNCoreMLModel(for: model) else {
            return nil
        }

        cachedModel = visionModel
        return visionModel
    }

    private static func classify(
        photoData: Data,
        using visionModel: VNCoreMLModel
    ) -> [FoodVenueExteriorLabel]? {
        guard let requestInput = imageRequestInput(photoData: photoData) else {
            return nil
        }

        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop

        do {
            try requestInput.handler.perform([request])
        } catch {
            return nil
        }

        guard let results = request.results as? [VNClassificationObservation] else {
            return nil
        }

        return results.prefix(6).map { observation in
            FoodVenueExteriorLabel(
                identifier: observation.identifier.lowercased(),
                confidence: Double(observation.confidence)
            )
        }
    }

    private static func classifyWithBuiltInVision(photoData: Data) -> [FoodVenueExteriorLabel] {
        guard let requestInput = imageRequestInput(photoData: photoData) else {
            return []
        }

        let request = VNClassifyImageRequest()

        do {
            try requestInput.handler.perform([request])
        } catch {
            return []
        }

        return (request.results ?? []).prefix(8).map { observation in
            FoodVenueExteriorLabel(
                identifier: observation.identifier.lowercased(),
                confidence: Double(observation.confidence)
            )
        }
    }

    private static func imageRequestInput(photoData: Data) -> (handler: VNImageRequestHandler, orientation: CGImagePropertyOrientation)? {
        guard
            let source = CGImageSourceCreateWithData(photoData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)

        return (handler, orientation)
    }

    private static func maxLabelConfidence(
        in labels: [FoodVenueExteriorLabel],
        identifiers: Set<String>,
        keywords: [String]
    ) -> Double {
        labels
            .filter { label in
                identifiers.contains(label.identifier)
                    || keywords.contains { keyword in
                        label.identifier.contains(keyword)
                    }
            }
            .map(\.confidence)
            .max() ?? 0
    }
}
