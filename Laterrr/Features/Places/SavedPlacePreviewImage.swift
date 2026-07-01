import SwiftUI

struct SavedPlacePreviewImage: View {
    let place: SavedPlace
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var fetchedSnapshotData: Data?

    var body: some View {
        Group {
            if let previewData, let image = UIImage(data: previewData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                CrosshatchPlaceholder(caption: height >= 100 ? "No photo" : nil)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: place.id) {
            await loadLookAroundPreviewIfNeeded()
        }
    }

    private var previewData: Data? {
        place.photoData ?? fetchedSnapshotData
    }

    @MainActor
    private func loadLookAroundPreviewIfNeeded() async {
        guard place.source == .tiktok else { return }
        guard place.photoData == nil else { return }
        guard fetchedSnapshotData == nil else { return }

        fetchedSnapshotData = await LookAroundSnapshotService.snapshotData(for: place.coordinate)
    }
}
