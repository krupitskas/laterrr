import SwiftUI

struct SavedPlacePreviewImage: View {
    let place: SavedPlace
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @State private var fetchedSnapshotData: Data?

    var body: some View {
        // The image lives in an overlay so a wide photo can never stretch the
        // layout past the proposed width; the clear base defines the frame.
        Color.clear
            .frame(width: width, height: height)
            .overlay {
                if let previewData, let image = UIImage(data: previewData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    CrosshatchPlaceholder(caption: height >= 100 ? "No photo" : nil)
                }
            }
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
