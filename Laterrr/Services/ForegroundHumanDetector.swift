import ImageIO
import Vision

struct ForegroundHumanAssessment: Sendable {
    let hasDominantForegroundPerson: Bool
    let faceCount: Int
    let largestFaceArea: Double
    let centeredFaceArea: Double
    let largestHumanArea: Double
    let centeredHumanArea: Double
}

enum ForegroundHumanDetector {
    private static let queue = DispatchQueue(label: "Laterrr.foreground.human", qos: .userInitiated)

    static func assess(photoData: Data) async -> ForegroundHumanAssessment {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: performAssessment(photoData: photoData))
            }
        }
    }

    private static func performAssessment(photoData: Data) -> ForegroundHumanAssessment {
        guard let requestInput = imageRequestInput(photoData: photoData) else {
            return ForegroundHumanAssessment(
                hasDominantForegroundPerson: false,
                faceCount: 0,
                largestFaceArea: 0,
                centeredFaceArea: 0,
                largestHumanArea: 0,
                centeredHumanArea: 0
            )
        }

        let faceRequest = VNDetectFaceRectanglesRequest()
        let humanRequest = VNDetectHumanRectanglesRequest()
        humanRequest.upperBodyOnly = false

        do {
            try requestInput.handler.perform([faceRequest, humanRequest])
        } catch {
            return ForegroundHumanAssessment(
                hasDominantForegroundPerson: false,
                faceCount: 0,
                largestFaceArea: 0,
                centeredFaceArea: 0,
                largestHumanArea: 0,
                centeredHumanArea: 0
            )
        }

        let faces = faceRequest.results ?? []
        let humans = humanRequest.results ?? []

        let largestFaceArea = faces.map { area(of: $0.boundingBox) }.max() ?? 0
        let centeredFaceArea = faces
            .filter { isCentered($0.boundingBox) }
            .map { area(of: $0.boundingBox) }
            .max() ?? 0

        let largestHumanArea = humans.map { area(of: $0.boundingBox) }.max() ?? 0
        let centeredHumanArea = humans
            .filter { isCentered($0.boundingBox) }
            .map { area(of: $0.boundingBox) }
            .max() ?? 0

        let hasDominantForegroundPerson =
            centeredFaceArea >= 0.018
            || largestFaceArea >= 0.045
            || centeredHumanArea >= 0.16
            || largestHumanArea >= 0.30

        return ForegroundHumanAssessment(
            hasDominantForegroundPerson: hasDominantForegroundPerson,
            faceCount: faces.count,
            largestFaceArea: largestFaceArea,
            centeredFaceArea: centeredFaceArea,
            largestHumanArea: largestHumanArea,
            centeredHumanArea: centeredHumanArea
        )
    }

    private static func area(of rect: CGRect) -> Double {
        Double(rect.width * rect.height)
    }

    private static func isCentered(_ rect: CGRect) -> Bool {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = center.x - 0.5
        let dy = center.y - 0.5
        return sqrt((dx * dx) + (dy * dy)) <= 0.28
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
}
