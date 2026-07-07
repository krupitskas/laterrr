import CoreLocation
import FoundationModels
import SwiftData
import SwiftUI

// MARK: - Guided generation schema

@Generable
struct ConciergeResponse {
    @Guide(description: "Exactly three picks from the provided saved places, best match first.", .count(3))
    let picks: [ConciergePick]
}

@Generable
struct ConciergePick {
    @Guide(description: "The place id copied exactly from the list.")
    let placeID: String

    @Guide(description: "One or two short sentences on why this place fits the request.")
    let reason: String
}

// MARK: - Chat model

@MainActor
final class PlacesChatModel: ObservableObject {
    struct Pick: Identifiable {
        let id = UUID()
        let placeID: UUID
        let name: String
        let detailLine: String
        let reason: String
    }

    enum Entry: Identifiable {
        case user(id: UUID, text: String)
        case assistant(id: UUID, text: String)
        case picks(id: UUID, picks: [Pick])
        case downloadOffer(id: UUID)

        var id: UUID {
            switch self {
            case let .user(id, _), let .assistant(id, _), let .picks(id, _), let .downloadOffer(id):
                return id
            }
        }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isThinking = false
    @Published private(set) var isDownloadingModel = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isMLXReady = MLXConciergeEngine.isSupported && MLXConciergeEngine.isModelDownloaded

    private var pendingRequest: String?
    private var hasOfferedDownload = false

    private let locationStore = LocationStore()
    private var session: LanguageModelSession?

    private static let instructions = """
    You are the concierge for laterrr, an app where people save cafes, restaurants, and bars \
    they want to visit later. You will receive the user's saved places (with id, name, category, \
    cuisine guesses, address, distance from the user, and notes) and a request. Pick exactly the \
    three places from the list that best fit the request, best first. Prefer closer places when \
    the request implies proximity. Copy each place id exactly as given. Keep every reason short, \
    concrete, and warm.
    """

    private var hasExplainedFallback = false

    var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }

        return false
    }

    var unavailabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible:
                return "This device can't run Apple Intelligence, so I'll match by your tags and distances instead."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is off or unsupported for your device language — I'll match by your tags and distances instead. (It needs a supported device and Siri language, like English.)"
            case .modelNotReady:
                return "Apple Intelligence is still downloading its model — matching by tags and distances for now."
            @unknown default:
                return "The on-device model isn't available — matching by tags and distances instead."
            }
        }
    }

    func prepare(places: [SavedPlace]) {
        locationStore.requestAuthorizationIfNeeded()

        guard entries.isEmpty else { return }

        entries.append(.assistant(id: UUID(), text: welcomeMessage(places: places)))

        if unavailabilityMessage == nil, session == nil {
            let session = LanguageModelSession(instructions: Self.instructions)
            session.prewarm()
            self.session = session
        }
    }

    func send(_ text: String, places: [SavedPlace]) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }

        entries.append(.user(id: UUID(), text: trimmed))

        guard places.count >= 3 else {
            entries.append(.assistant(
                id: UUID(),
                text: "Save at least three places first — then I have something to choose from."
            ))
            return
        }

        if isModelAvailable {
            respondWithFoundationModel(trimmed, places: places)
            return
        }

        if MLXConciergeEngine.isSupported {
            if isMLXReady {
                respondWithMLX(trimmed, places: places)
            } else if isDownloadingModel {
                pendingRequest = trimmed
                entries.append(.assistant(
                    id: UUID(),
                    text: "Still downloading the concierge — I'll answer this as soon as it lands."
                ))
            } else {
                pendingRequest = trimmed

                if hasOfferedDownload {
                    entries.append(.assistant(
                        id: UUID(),
                        text: "Tap “Download concierge” above and I'll take it from there."
                    ))
                } else {
                    hasOfferedDownload = true
                    entries.append(.assistant(
                        id: UUID(),
                        text: "Apple Intelligence isn't available here, but I can download a local concierge instead — about 1 GB, once, fully on-device."
                    ))
                    entries.append(.downloadOffer(id: UUID()))
                }
            }
            return
        }

        if !hasExplainedFallback, let unavailabilityMessage {
            hasExplainedFallback = true
            entries.append(.assistant(id: UUID(), text: unavailabilityMessage))
        }

        entries.append(.picks(id: UUID(), picks: fallbackPicks(request: trimmed, places: places)))
    }

    func startModelDownload(places: [SavedPlace]) {
        guard !isDownloadingModel, !isMLXReady else { return }

        isDownloadingModel = true
        downloadProgress = 0

        Task { [weak self] in
            guard let self else { return }

            do {
                try await MLXConciergeEngine.shared.prepare { fraction in
                    Task { @MainActor [weak self] in
                        self?.downloadProgress = fraction
                    }
                }

                isDownloadingModel = false
                isMLXReady = true
                entries.append(.assistant(id: UUID(), text: "Concierge downloaded — all set."))

                if let pendingRequest {
                    self.pendingRequest = nil
                    respondWithMLX(pendingRequest, places: places)
                }
            } catch {
                isDownloadingModel = false
                entries.append(.assistant(
                    id: UUID(),
                    text: "The download didn't finish — check your connection and tap it again."
                ))
            }
        }
    }

    private func respondWithFoundationModel(_ request: String, places: [SavedPlace]) {
        isThinking = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let session = self.session ?? LanguageModelSession(instructions: Self.instructions)
                self.session = session

                let prompt = """
                Saved places:
                \(contextBlock(for: places))

                Request: \(request)

                Pick exactly three places from the list above that best fit the request.
                """

                let response = try await session.respond(to: prompt, generating: ConciergeResponse.self)
                handle(response.content, places: places)
            } catch {
                session = nil
                entries.append(.assistant(
                    id: UUID(),
                    text: "I lost my train of thought — ask me that again."
                ))
            }

            isThinking = false
        }
    }

    private func respondWithMLX(_ request: String, places: [SavedPlace]) {
        isThinking = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let prompt = """
                Saved places:
                \(contextBlock(for: places))

                Request: \(request)

                Reply with ONLY a JSON array of exactly three objects, best match first, like:
                [{"id":"<place id copied exactly>","reason":"<one short sentence>"}]
                No other text. /no_think
                """

                let output = try await MLXConciergeEngine.shared.respond(
                    instructions: Self.instructions,
                    prompt: prompt
                )

                let picks = parsePicks(from: output, places: places)

                if picks.isEmpty {
                    entries.append(.picks(id: UUID(), picks: fallbackPicks(request: request, places: places)))
                } else {
                    entries.append(.picks(id: UUID(), picks: Array(picks.prefix(3))))
                }
            } catch {
                entries.append(.assistant(
                    id: UUID(),
                    text: "The local concierge stumbled — matching by tags instead."
                ))
                entries.append(.picks(id: UUID(), picks: fallbackPicks(request: request, places: places)))
            }

            isThinking = false
        }
    }

    // Small local models don't do guided generation, so parse leniently:
    // strip thinking blocks, find the JSON array, decode what we can.
    private func parsePicks(from output: String, places: [SavedPlace]) -> [Pick] {
        var text = output

        while
            let start = text.range(of: "<think>"),
            let end = text.range(of: "</think>"),
            start.lowerBound < end.upperBound {
            text.removeSubrange(start.lowerBound ..< end.upperBound)
        }

        guard
            let first = text.firstIndex(of: "["),
            let last = text.lastIndex(of: "]"),
            first < last
        else {
            return []
        }

        struct RawPick: Decodable {
            let id: String
            let reason: String
        }

        let json = String(text[first ... last])
        guard let rawPicks = try? JSONDecoder().decode([RawPick].self, from: Data(json.utf8)) else {
            return []
        }

        return resolvedPicks(
            from: rawPicks.map { (identifier: $0.id, reason: $0.reason) },
            places: places
        )
    }

    private func welcomeMessage(places: [SavedPlace]) -> String {
        let example = places.flatMap(\.cuisineTags).randomElement().map { "a \($0.lowercased()) spot" }
            ?? "a fancy french dinner"
        return "Don't know where to go? Ask for \(example) close to you — I'll pick three from your places."
    }

    // Local scoring used when Apple Intelligence isn't available: matches the
    // request against names, cuisine tags, categories, notes, and addresses,
    // with proximity as a tie-breaker — always returns three picks.
    private func fallbackPicks(request: String, places: [SavedPlace]) -> [Pick] {
        let tokens = request
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }

        let userLocation = locationStore.currentLocation

        let scored: [(place: SavedPlace, score: Double, distance: CLLocationDistance?)] = places.map { place in
            let haystacks: [(text: String, weight: Double)] = [
                (place.cuisineTags.joined(separator: " "), 4.0),
                (place.name, 3.0),
                (place.displayCategory, 2.5),
                (place.fullAddress, 1.5),
                (place.selectionReason + " " + place.matchedText, 1.0)
            ]

            var score = 0.0
            for token in tokens {
                for haystack in haystacks where haystack.text.lowercased().contains(token) {
                    score += haystack.weight
                }
            }

            var distance: CLLocationDistance?
            if let userLocation {
                let meters = userLocation.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                distance = meters
                // Small proximity boost so nearby matches win ties.
                score += max(0, 2 - meters / 1000) * 0.5
            }

            return (place, score, distance)
        }

        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }

            if let lhsDistance = lhs.distance, let rhsDistance = rhs.distance, lhsDistance != rhsDistance {
                return lhsDistance < rhsDistance
            }

            return lhs.place.createdAt > rhs.place.createdAt
        }

        return ranked.prefix(3).map { entry in
            var reasonParts: [String] = []

            let matchedTag = entry.place.cuisineTags.first {
                tokens.contains(where: $0.lowercased().contains)
            }

            if let matchedTag {
                reasonParts.append("Tagged \(matchedTag.lowercased())")
            } else if entry.score > 0 {
                reasonParts.append("Closest match to “\(request)” in your list")
            } else {
                reasonParts.append("A recent favorite from your list")
            }

            if let distance = entry.distance {
                reasonParts.append("\(Self.formattedDistance(distance)) from you")
            }

            return Pick(
                placeID: entry.place.id,
                name: entry.place.name,
                detailLine: detailLine(for: entry.place),
                reason: reasonParts.joined(separator: " · ") + "."
            )
        }
    }

    private func contextBlock(for places: [SavedPlace]) -> String {
        let userLocation = locationStore.currentLocation

        return places.prefix(60).map { place in
            var parts = [
                "id: \(place.id.uuidString)",
                "name: \(place.name)"
            ]

            if !place.displayCategory.isEmpty {
                parts.append("category: \(place.displayCategory)")
            }

            if !place.cuisineTags.isEmpty {
                parts.append("cuisine: \(place.cuisineTags.joined(separator: ", "))")
            }

            if !place.shortAddress.isEmpty {
                parts.append("address: \(place.shortAddress)")
            }

            if let userLocation {
                let distance = userLocation.distance(
                    from: CLLocation(latitude: place.latitude, longitude: place.longitude)
                )
                parts.append("distance: \(Self.formattedDistance(distance))")
            }

            if !place.selectionReason.isEmpty {
                parts.append("note: \(place.selectionReason.prefix(120))")
            }

            return "- " + parts.joined(separator: " | ")
        }
        .joined(separator: "\n")
    }

    private func handle(_ response: ConciergeResponse, places: [SavedPlace]) {
        let picks = resolvedPicks(
            from: response.picks.map { (identifier: $0.placeID, reason: $0.reason) },
            places: places
        )

        if picks.isEmpty {
            entries.append(.assistant(
                id: UUID(),
                text: "I couldn't line that up with your saved places — try wording it differently."
            ))
        } else {
            entries.append(.picks(id: UUID(), picks: Array(picks.prefix(3))))
        }
    }

    private func resolvedPicks(
        from rawPicks: [(identifier: String, reason: String)],
        places: [SavedPlace]
    ) -> [Pick] {
        var picks: [Pick] = []
        var usedPlaceIDs = Set<UUID>()

        for rawPick in rawPicks {
            let identifier = rawPick.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let place = places.first { $0.id.uuidString.caseInsensitiveCompare(identifier) == .orderedSame }
                ?? places.first { $0.name.caseInsensitiveCompare(identifier) == .orderedSame }

            guard let place, usedPlaceIDs.insert(place.id).inserted else { continue }

            picks.append(
                Pick(
                    placeID: place.id,
                    name: place.name,
                    detailLine: detailLine(for: place),
                    reason: rawPick.reason
                )
            )
        }

        return picks
    }

    private func detailLine(for place: SavedPlace) -> String {
        var parts: [String] = []

        if !place.displayCategory.isEmpty {
            parts.append(place.displayCategory)
        }

        parts.append(contentsOf: place.cuisineTags.prefix(2))

        if let userLocation = locationStore.currentLocation {
            let distance = userLocation.distance(
                from: CLLocation(latitude: place.latitude, longitude: place.longitude)
            )
            parts.append(Self.formattedDistance(distance))
        }

        return parts.joined(separator: " · ")
    }

    private static func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }

        return String(format: "%.1f km", meters / 1000)
    }
}

// MARK: - Chat view

struct PlacesChatView: View {
    @ObservedObject var model: PlacesChatModel
    let openPlace: (SavedPlace) -> Void

    @Query(sort: \SavedPlace.createdAt, order: .reverse) private var savedPlaces: [SavedPlace]
    @State private var draft = ""
    @State private var keyboardTop = CGFloat.infinity
    @FocusState private var isInputFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let keyboardOverlap = max(0, geometry.frame(in: .global).maxY - keyboardTop)

            ZStack {
                LaterrrBackground()

                VStack(spacing: 0) {
                    header
                    messages
                    inputBar
                }
                .padding(.bottom, keyboardOverlap)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            model.prepare(places: savedPlaces)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        ) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }

            withAnimation(.easeOut(duration: 0.25)) {
                keyboardTop = frame.origin.y
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Concierge", color: LaterrrPalette.inkSecondary)

            Text("Hmmm.")
                .font(LaterrrTypography.display(44))
                .foregroundStyle(LaterrrPalette.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.entries) { entry in
                        entryView(entry)
                            .id(entry.id)
                    }

                    if model.isDownloadingModel {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroText(
                                "Download concierge — \(Int((model.downloadProgress * 100).rounded()))%",
                                size: 9,
                                kerning: 1.5,
                                color: LaterrrPalette.inkSecondary
                            )

                            InkProgressBar(value: model.downloadProgress)
                        }
                        .id("downloading")
                    }

                    if model.isThinking {
                        HStack(spacing: 10) {
                            InkSpinner(size: 16)
                            MicroText("Thinking", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.entries.count) { _, _ in
                if let lastID = model.entries.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.isThinking) { _, isThinking in
                if isThinking {
                    withAnimation {
                        proxy.scrollTo("thinking", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(_ entry: PlacesChatModel.Entry) -> some View {
        switch entry {
        case let .user(_, text):
            Text(text)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.canvas)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(LaterrrPalette.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)

        case let .assistant(_, text):
            Text(text)
                .font(LaterrrTypography.accent(19))
                .foregroundStyle(LaterrrPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .picks(_, picks):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                    pickCard(pick, index: index)
                }
            }

        case .downloadOffer:
            Button {
                model.startModelDownload(places: savedPlaces)
            } label: {
                Text(model.isMLXReady ? "Concierge ready" : "Download concierge — 1 GB")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.inkPrimary)
            .disabled(model.isDownloadingModel || model.isMLXReady)
        }
    }

    private func pickCard(_ pick: PlacesChatModel.Pick, index: Int) -> some View {
        Button {
            if let place = savedPlaces.first(where: { $0.id == pick.placeID }) {
                openPlace(place)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                MicroText(String(format: "%02d", index + 1), color: LaterrrPalette.inkTertiary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(pick.name)
                        .font(LaterrrTypography.display(22))
                        .foregroundStyle(LaterrrPalette.ink)
                        .multilineTextAlignment(.leading)

                    if !pick.detailLine.isEmpty {
                        MicroText(pick.detailLine, size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)
                            .lineLimit(1)
                    }

                    Text(pick.reason)
                        .font(LaterrrTypography.body(.footnote))
                        .foregroundStyle(LaterrrPalette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            HairlineDivider()

            HStack(spacing: 12) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("I want sushi close to me…")
                        .font(LaterrrTypography.accent(17))
                        .foregroundStyle(LaterrrPalette.inkTertiary)
                )
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.ink)
                .tint(LaterrrPalette.ink)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(send)

                Button(action: send) {
                    Text("Ask")
                }
                .buttonStyle(.inkPrimary)
                .disabled(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(LaterrrPalette.canvas)
    }

    private func send() {
        model.send(draft, places: savedPlaces)
        draft = ""
    }
}
