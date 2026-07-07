import CoreLocation
import Foundation
import SwiftData

@Model
final class SavedPlace {
    @Attribute(.unique) var id: UUID
    @Attribute(.spotlight) var name: String
    var shortAddress: String
    var fullAddress: String
    var category: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date
    var confidence: Double
    var matchedText: String
    var selectionReason: String
    var analysisMode: String
    var sourceRawValue: String
    var websiteURLString: String?
    var cuisineTagsRawValue: String?

    @Attribute(.externalStorage) var photoData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        shortAddress: String,
        fullAddress: String,
        category: String,
        latitude: Double,
        longitude: Double,
        createdAt: Date = .now,
        confidence: Double,
        matchedText: String,
        selectionReason: String,
        analysisMode: String,
        source: SavedPlaceSource = .camera,
        websiteURLString: String? = nil,
        cuisineTags: [String] = [],
        photoData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.shortAddress = shortAddress
        self.fullAddress = fullAddress
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.confidence = confidence
        self.matchedText = matchedText
        self.selectionReason = selectionReason
        self.analysisMode = analysisMode
        self.sourceRawValue = source.rawValue
        self.websiteURLString = websiteURLString
        self.cuisineTagsRawValue = cuisineTags.isEmpty ? nil : cuisineTags.joined(separator: ",")
        self.photoData = photoData
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var websiteURL: URL? {
        guard let websiteURLString, !websiteURLString.isEmpty else {
            return nil
        }

        return URL(string: websiteURLString)
    }

    var source: SavedPlaceSource {
        get { SavedPlaceSource(rawValue: sourceRawValue) ?? .camera }
        set { sourceRawValue = newValue.rawValue }
    }

    /// On-device MobileCLIP guesses like "Sushi" or "Fine Dining".
    var cuisineTags: [String] {
        get {
            (cuisineTagsRawValue ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            cuisineTagsRawValue = newValue.isEmpty ? nil : newValue.joined(separator: ",")
        }
    }

    /// Older saves stored raw MapKit identifiers mangled by `.capitalized`
    /// (e.g. "Mkpoicategoryrestaurant"); clean those up for display.
    var displayCategory: String {
        var name = category.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            return ""
        }

        if name.lowercased().hasPrefix("mkpoicategory") {
            name = String(name.dropFirst("mkpoicategory".count))
        }

        name = name.replacingOccurrences(
            of: "(?<=[a-z])(?=[A-Z])",
            with: " ",
            options: .regularExpression
        )

        return name.capitalized
    }
}

struct SavedPlaceDraft {
    let name: String
    let shortAddress: String
    let fullAddress: String
    let category: String
    let latitude: Double
    let longitude: Double
    let createdAt: Date
    let confidence: Double
    let matchedText: String
    let selectionReason: String
    let analysisMode: String
    let source: SavedPlaceSource
    let websiteURLString: String?
    var cuisineTags: [String] = []
    let photoData: Data?

    func makeModel() -> SavedPlace {
        SavedPlace(
            name: name,
            shortAddress: shortAddress,
            fullAddress: fullAddress,
            category: category,
            latitude: latitude,
            longitude: longitude,
            createdAt: createdAt,
            confidence: confidence,
            matchedText: matchedText,
            selectionReason: selectionReason,
            analysisMode: analysisMode,
            source: source,
            websiteURLString: websiteURLString,
            cuisineTags: cuisineTags,
            photoData: photoData
        )
    }
}

enum SavedPlaceSaveOutcome {
    case inserted(SavedPlace)
    case merged(SavedPlace)

    var place: SavedPlace {
        switch self {
        case let .inserted(place), let .merged(place):
            return place
        }
    }

    var wasInserted: Bool {
        if case .inserted = self {
            return true
        }

        return false
    }
}

enum SavedPlaceStore {
    static func save(_ draft: SavedPlaceDraft, in modelContext: ModelContext) -> SavedPlaceSaveOutcome {
        let descriptor = FetchDescriptor<SavedPlace>()
        let existingPlaces = (try? modelContext.fetch(descriptor)) ?? []

        if let existingPlace = existingPlaces.first(where: { isDuplicate(existing: $0, incoming: draft) }) {
            merge(existingPlace, with: draft)
            try? modelContext.save()
            return .merged(existingPlace)
        }

        let place = draft.makeModel()
        modelContext.insert(place)
        try? modelContext.save()
        return .inserted(place)
    }

    private static func isDuplicate(existing: SavedPlace, incoming: SavedPlaceDraft) -> Bool {
        let normalizedExistingName = normalized(existing.name)
        let normalizedIncomingName = normalized(incoming.name)
        let normalizedExistingFullAddress = normalized(existing.fullAddress)
        let normalizedIncomingFullAddress = normalized(incoming.fullAddress)
        let normalizedExistingShortAddress = normalized(existing.shortAddress)
        let normalizedIncomingShortAddress = normalized(incoming.shortAddress)

        let nameMatches = !normalizedExistingName.isEmpty && normalizedExistingName == normalizedIncomingName
        let fullAddressMatches = !normalizedExistingFullAddress.isEmpty
            && normalizedExistingFullAddress == normalizedIncomingFullAddress
        let shortAddressMatches = !normalizedExistingShortAddress.isEmpty
            && normalizedExistingShortAddress == normalizedIncomingShortAddress

        let distance = CLLocation(
            latitude: existing.latitude,
            longitude: existing.longitude
        ).distance(
            from: CLLocation(latitude: incoming.latitude, longitude: incoming.longitude)
        )

        return (nameMatches && (fullAddressMatches || shortAddressMatches || distance <= 60))
            || ((fullAddressMatches || shortAddressMatches) && distance <= 45)
    }

    private static func merge(_ existing: SavedPlace, with incoming: SavedPlaceDraft) {
        let existingPriority = existing.source.mergePriority
        let incomingPriority = incoming.source.mergePriority

        if incomingPriority > existingPriority {
            existing.source = incoming.source
        }

        if incoming.confidence > existing.confidence {
            existing.confidence = incoming.confidence
        }

        if existing.selectionReason.isEmpty || incoming.selectionReason.count > existing.selectionReason.count {
            existing.selectionReason = incoming.selectionReason
        }

        if existing.analysisMode.isEmpty || incomingPriority >= existingPriority {
            existing.analysisMode = incoming.analysisMode
        }

        if existing.matchedText.isEmpty || incoming.matchedText.count > existing.matchedText.count {
            existing.matchedText = incoming.matchedText
        }

        if existing.websiteURLString == nil || existing.websiteURLString?.isEmpty == true {
            existing.websiteURLString = incoming.websiteURLString
        }

        if existing.cuisineTags.isEmpty, !incoming.cuisineTags.isEmpty {
            existing.cuisineTags = incoming.cuisineTags
        }

        if incoming.photoData != nil && (existing.photoData == nil || incomingPriority >= existingPriority) {
            existing.photoData = incoming.photoData
        }

        if existing.fullAddress.isEmpty || incoming.fullAddress.count > existing.fullAddress.count {
            existing.fullAddress = incoming.fullAddress
        }

        if existing.shortAddress.isEmpty || incoming.shortAddress.count > existing.shortAddress.count {
            existing.shortAddress = incoming.shortAddress
        }

        if existing.category.isEmpty {
            existing.category = incoming.category
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }
}

private extension SavedPlaceSource {
    var mergePriority: Int {
        switch self {
        case .tiktok:
            return 0
        case .photoLibrary:
            return 1
        case .camera:
            return 2
        }
    }
}
