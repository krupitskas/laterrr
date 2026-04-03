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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LaterrrPalette.accentSoft.opacity(0.55))
                    .overlay {
                        Image(systemName: place.source == .tiktok ? "binoculars.fill" : "cup.and.saucer.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(LaterrrPalette.textPrimary)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
