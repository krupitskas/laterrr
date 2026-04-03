import CoreImage
import CoreML
import Foundation

private struct MobileCLIPPromptDefinition {
    enum Kind {
        case positive
        case context
        case negative
    }

    let identifier: String
    let text: String
    let kind: Kind
}

private struct MobileCLIPPromptEmbedding {
    let prompt: MobileCLIPPromptDefinition
    let embedding: [Float]
}

private struct MobileCLIPPromptScore {
    let prompt: MobileCLIPPromptDefinition
    let similarity: Double
}

actor MobileCLIPVenueScorer {
    static let shared = MobileCLIPVenueScorer()

    private static let imageModelName = "mobileclip_s0_image"
    private static let textModelName = "mobileclip_s0_text"
    private static let tokenizerSubdirectory = "MobileCLIP/Tokenizer"
    private static let targetImageSize = CGSize(width: 256, height: 256)
    private static let promptCatalog: [MobileCLIPPromptDefinition] = [
        .init(identifier: "cafe_exterior", text: "a photo of the exterior of a cafe", kind: .positive),
        .init(identifier: "cafe_storefront", text: "a photo of a cafe storefront", kind: .positive),
        .init(identifier: "cafe_exterior_sign", text: "a photo of a cafe sign above a storefront", kind: .positive),
        .init(identifier: "coffee_shop_exterior", text: "a photo of the exterior of a coffee shop", kind: .positive),
        .init(identifier: "restaurant_exterior", text: "a photo of the exterior of a restaurant", kind: .positive),
        .init(identifier: "restaurant_storefront", text: "a street photo of a restaurant storefront", kind: .positive),
        .init(identifier: "restaurant_exterior_sign", text: "a photo of a restaurant sign above an entrance", kind: .positive),
        .init(identifier: "bakery_exterior", text: "a photo of a bakery storefront", kind: .positive),
        .init(identifier: "bistro_exterior", text: "a photo of a bistro exterior", kind: .positive),
        .init(identifier: "brasserie_exterior", text: "a photo of a brasserie facade", kind: .positive),
        .init(identifier: "cafe_terrace", text: "a photo of a cafe terrace from the street", kind: .positive),
        .init(identifier: "storefront_exterior", text: "a photo of a storefront on a city street", kind: .context),
        .init(identifier: "building_facade", text: "a photo of a building facade", kind: .context),
        .init(identifier: "shop_exterior", text: "a photo of a shop exterior", kind: .context),
        .init(identifier: "storefront_signage", text: "a photo of storefront signage on a building exterior", kind: .context),
        .init(identifier: "shop_entrance", text: "a photo of a shop entrance from the sidewalk", kind: .context),
        .init(identifier: "urban_streetfront", text: "a photo of an urban streetfront", kind: .context),
        .init(identifier: "awning_storefront", text: "a photo of a storefront with an awning", kind: .context),
        .init(identifier: "home_interior", text: "a photo of a home interior", kind: .negative),
        .init(identifier: "living_room_couch", text: "a photo of a couch in a living room", kind: .negative),
        .init(identifier: "painting", text: "a photo of a painting on a wall", kind: .negative),
        .init(identifier: "dog_indoors", text: "a photo of a dog inside a home", kind: .negative),
        .init(identifier: "cat_indoors", text: "a photo of a cat inside a home", kind: .negative),
        .init(identifier: "menu_closeup", text: "a close up photo of a restaurant menu", kind: .negative),
        .init(identifier: "receipt", text: "a close up photo of a paper receipt", kind: .negative),
        .init(identifier: "bathroom_sign", text: "a photo of a bathroom sign", kind: .negative),
        .init(identifier: "toilet_sign", text: "a photo of a toilet sign", kind: .negative),
        .init(identifier: "office_sign", text: "a photo of an office door sign", kind: .negative),
        .init(identifier: "food_closeup", text: "a close up photo of food on a table", kind: .negative),
        .init(identifier: "drink_closeup", text: "a close up photo of a drink on a table", kind: .negative),
        .init(identifier: "restaurant_interior", text: "a photo of the inside of a restaurant", kind: .negative),
        .init(identifier: "cafe_interior", text: "a photo of the inside of a cafe", kind: .negative),
        .init(identifier: "person_at_restaurant_table", text: "a portrait of a person sitting at a restaurant table", kind: .negative),
        .init(identifier: "people_dining_indoors", text: "a photo of people dining indoors", kind: .negative),
        .init(identifier: "selfie_in_cafe", text: "a selfie taken inside a cafe", kind: .negative),
        .init(identifier: "indoor_dining_room", text: "a photo of an indoor dining room", kind: .negative)
    ]

    private let ciContext = CIContext()
    private var didAttemptLoad = false
    private var didFailToLoad = false
    private var imageModel: MLModel?
    private var textModel: MLModel?
    private var promptEmbeddings: [MobileCLIPPromptEmbedding] = []

    func assess(photoData: Data) async -> FoodVenueExteriorAssessment? {
        do {
            try loadIfNeeded()
            guard
                let imageModel,
                !promptEmbeddings.isEmpty,
                let imageEmbedding = try imageEmbedding(from: photoData, using: imageModel)
            else {
                return nil
            }

            let scores = promptEmbeddings.map { promptEmbedding in
                MobileCLIPPromptScore(
                    prompt: promptEmbedding.prompt,
                    similarity: Double(
                        cosineSimilarity(promptEmbedding.embedding, imageEmbedding)
                    )
                )
            }

            let positiveConfidence = bestSimilarity(in: scores, kind: .positive)
            let contextConfidence = bestSimilarity(in: scores, kind: .context)
            let negativeConfidence = bestSimilarity(in: scores, kind: .negative)
            let confidence = max(
                0,
                positiveConfidence + (contextConfidence * 0.45) - (negativeConfidence * 1.05)
            )

            let isLikelyExteriorVenue = positiveConfidence >= 0.22
                && (
                    (contextConfidence >= 0.17 && positiveConfidence >= 0.17)
                        || positiveConfidence >= (negativeConfidence + 0.04)
                )
            let isLikelyExteriorContext = contextConfidence >= 0.18
                && contextConfidence >= (negativeConfidence + 0.01)

            let labels = scores
                .sorted { $0.similarity > $1.similarity }
                .prefix(6)
                .map { score in
                    FoodVenueExteriorLabel(
                        identifier: score.prompt.identifier,
                        confidence: score.similarity
                    )
                }

            return FoodVenueExteriorAssessment(
                isLikelyExteriorVenue: isLikelyExteriorVenue,
                isLikelyExteriorContext: isLikelyExteriorContext,
                confidence: confidence,
                positiveConfidence: positiveConfidence,
                contextConfidence: contextConfidence,
                negativeConfidence: negativeConfidence,
                labels: labels,
                source: .mobileCLIP
            )
        } catch {
            didFailToLoad = true
            return nil
        }
    }

    private func loadIfNeeded() throws {
        if didFailToLoad {
            throw CLIPTokenizerError.missingVocabulary
        }

        if didAttemptLoad {
            return
        }

        didAttemptLoad = true

        let tokenizer = try CLIPTokenizer(resourceSubdirectory: Self.tokenizerSubdirectory)
        let imageModel = try loadModel(named: Self.imageModelName)
        let textModel = try loadModel(named: Self.textModelName)
        var promptEmbeddings: [MobileCLIPPromptEmbedding] = []
        promptEmbeddings.reserveCapacity(Self.promptCatalog.count)
        for prompt in Self.promptCatalog {
            let embedding = try textEmbedding(
                for: prompt.text,
                using: tokenizer,
                model: textModel
            )
            promptEmbeddings.append(
                MobileCLIPPromptEmbedding(
                    prompt: prompt,
                    embedding: embedding
                )
            )
        }

        self.imageModel = imageModel
        self.textModel = textModel
        self.promptEmbeddings = promptEmbeddings
    }

    private func loadModel(named name: String) throws -> MLModel {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        if let compiledURL = bundleURL(for: name, extension: "mlmodelc") {
            return try MLModel(contentsOf: compiledURL, configuration: configuration)
        }

        guard let packageURL = bundleURL(for: name, extension: "mlpackage") else {
            throw CLIPTokenizerError.missingVocabulary
        }

        let compiledURL = try MLModel.compileModel(at: packageURL)
        return try MLModel(contentsOf: compiledURL, configuration: configuration)
    }

    private func bundleURL(for name: String, extension fileExtension: String) -> URL? {
        if let directURL = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "MobileCLIP"
        ) {
            return directURL
        }

        if let directURL = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return directURL
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            return nil
        }

        let candidates = [
            resourceURL.appendingPathComponent("MobileCLIP/\(name).\(fileExtension)"),
            resourceURL.appendingPathComponent("\(name).\(fileExtension)")
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func textEmbedding(
        for prompt: String,
        using tokenizer: CLIPTokenizer,
        model: MLModel
    ) throws -> [Float] {
        let tokenIDs = tokenizer.encodeFull(text: prompt)
        let inputArray = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for (index, tokenID) in tokenIDs.enumerated() {
            inputArray[index] = NSNumber(value: tokenID)
        }

        let features = try MLDictionaryFeatureProvider(dictionary: [
            "text": MLFeatureValue(multiArray: inputArray)
        ])
        let output = try model.prediction(from: features)
        guard let embedding = output.featureValue(for: "final_emb_1")?.multiArrayValue else {
            return []
        }
        return embedding.floatArray
    }

    private func imageEmbedding(from photoData: Data, using model: MLModel) throws -> [Float]? {
        guard let pixelBuffer = makePixelBuffer(from: photoData) else {
            return nil
        }

        let features = try MLDictionaryFeatureProvider(dictionary: [
            "image": MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: features)
        guard let embedding = output.featureValue(for: "final_emb_1")?.multiArrayValue else {
            return nil
        }
        return embedding.floatArray
    }

    private func makePixelBuffer(from photoData: Data) -> CVPixelBuffer? {
        guard
            let image = CIImage(
                data: photoData,
                options: [.applyOrientationProperty: true]
            )?
            .cropToSquare()?
            .resize(size: Self.targetImageSize)
        else {
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            nil,
            Int(Self.targetImageSize.width),
            Int(Self.targetImageSize.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        ciContext.render(image, to: pixelBuffer)
        return pixelBuffer
    }

    private func bestSimilarity(
        in scores: [MobileCLIPPromptScore],
        kind: MobileCLIPPromptDefinition.Kind
    ) -> Double {
        scores
            .filter { $0.prompt.kind == kind }
            .map(\.similarity)
            .max() ?? 0
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }

        var dotProduct: Float = 0
        var lhsMagnitude: Float = 0
        var rhsMagnitude: Float = 0

        for index in lhs.indices {
            let lhsValue = lhs[index]
            let rhsValue = rhs[index]
            dotProduct += lhsValue * rhsValue
            lhsMagnitude += lhsValue * lhsValue
            rhsMagnitude += rhsValue * rhsValue
        }

        let denominator = sqrt(lhsMagnitude) * sqrt(rhsMagnitude)
        guard denominator > 0 else {
            return 0
        }

        return dotProduct / denominator
    }
}

private extension CIImage {
    func cropToSquare() -> CIImage? {
        let dimension = min(extent.width, extent.height)
        let originX = round((extent.width - dimension) / 2)
        let originY = round((extent.height - dimension) / 2)
        let cropRect = CGRect(x: originX, y: originY, width: dimension, height: dimension)
        return cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -originX, y: -originY))
    }

    func resize(size: CGSize) -> CIImage? {
        let scaleX = size.width / extent.width
        let scaleY = size.height / extent.height
        return transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    }
}

private extension MLMultiArray {
    var floatArray: [Float] {
        switch dataType {
        case .float16:
            return withUnsafeBufferPointer(ofType: Float16.self) { pointer in
                Array(pointer).map(Float.init)
            }
        case .float32:
            return withUnsafeBufferPointer(ofType: Float.self) { pointer in
                Array(pointer)
            }
        case .double:
            return withUnsafeBufferPointer(ofType: Double.self) { pointer in
                Array(pointer).map(Float.init)
            }
        default:
            return (0 ..< count).map { index in
                self[index].floatValue
            }
        }
    }

    func withUnsafeBufferPointer<T, Result>(
        ofType type: T.Type,
        _ body: (UnsafeBufferPointer<T>) -> Result
    ) -> Result {
        let pointer = dataPointer.bindMemory(to: T.self, capacity: count)
        return body(UnsafeBufferPointer(start: pointer, count: count))
    }
}
