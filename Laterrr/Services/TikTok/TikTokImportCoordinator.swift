import SwiftData
import SwiftUI

struct TikTokImportReviewState: Identifiable {
    let id = UUID()
    let deck: TikTokImportReviewDeck
    var currentIndex: Int = 0

    var currentVenue: TikTokResolvedVenue? {
        guard currentIndex < deck.venues.count else { return nil }
        return deck.venues[currentIndex]
    }

    var remainingCount: Int {
        max(deck.venues.count - currentIndex, 0)
    }
}

@MainActor
final class TikTokImportCoordinator: ObservableObject {
    enum EnqueueOutcome {
        case started
        case queued
    }

    @Published var reviewState: TikTokImportReviewState?
    @Published var isImporting = false
    @Published var alertMessage: String?

    private var activeTask: Task<Void, Never>?

    func processPendingImportsIfNeeded() {
        guard reviewState == nil else { return }
        guard activeTask == nil else { return }
        guard let pendingImport = TikTokPendingImportStore.pendingImports().first else { return }

        activeTask = Task {
            await importPending(pendingImport)
        }
    }

    func enqueueImport(from rawURLString: String) -> Result<EnqueueOutcome, TikTokImportURLParser.ParseError> {
        switch TikTokImportURLParser.parse(rawURLString) {
        case let .success(url):
            let willStartNow = reviewState == nil && activeTask == nil
            TikTokPendingImportStore.enqueue(url: url)
            processPendingImportsIfNeeded()
            return .success(willStartNow ? .started : .queued)
        case let .failure(error):
            return .failure(error)
        }
    }

    func saveCurrent(modelContext: ModelContext) {
        guard let currentReviewState = reviewState, let venue = currentReviewState.currentVenue else { return }

        let selectionReason = venue.sourceLine == venue.name
            ? "Imported from TikTok and confirmed in Apple Maps."
            : "Imported from TikTok as \(venue.sourceLine) and confirmed in Apple Maps as \(venue.name)."

        let place = SavedPlace(
            name: venue.name,
            shortAddress: venue.shortAddress,
            fullAddress: venue.fullAddress,
            category: venue.category,
            latitude: venue.latitude,
            longitude: venue.longitude,
            confidence: 0.92,
            matchedText: venue.sourceLine,
            selectionReason: selectionReason,
            analysisMode: "TikTok import + Apple Maps",
            source: .tiktok,
            websiteURLString: venue.websiteURL?.absoluteString,
            photoData: venue.lookAroundSnapshotData
        )

        modelContext.insert(place)
        try? modelContext.save()

        advanceReview()
    }

    func skipCurrent() {
        advanceReview()
    }

    func dismissAlert() {
        alertMessage = nil
    }

    private func importPending(_ pendingImport: PendingTikTokImport) async {
        isImporting = true

        guard let sourceURL = pendingImport.sourceURL else {
            TikTokPendingImportStore.remove(importID: pendingImport.id)
            isImporting = false
            activeTask = nil
            alertMessage = "laterrr could not read that shared TikTok link."
            return
        }

        do {
            let reviewDeck = try await TikTokImportRoutine.buildReviewDeck(from: sourceURL)
            TikTokPendingImportStore.remove(importID: pendingImport.id)
            isImporting = false
            activeTask = nil
            reviewState = TikTokImportReviewState(deck: reviewDeck)
        } catch {
            TikTokPendingImportStore.remove(importID: pendingImport.id)
            isImporting = false
            activeTask = nil
            alertMessage = error.localizedDescription
        }
    }

    private func advanceReview() {
        guard var currentReviewState = reviewState else { return }
        currentReviewState.currentIndex += 1

        if currentReviewState.currentIndex >= currentReviewState.deck.venues.count {
            reviewState = nil
            processPendingImportsIfNeeded()
        } else {
            reviewState = currentReviewState
        }
    }
}
