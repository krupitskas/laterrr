import Foundation
@preconcurrency import MapKit

enum LookAroundSnapshotService {
    static func snapshotData(for coordinate: CLLocationCoordinate2D) async -> Data? {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)

        guard let scene = try? await request.scene else {
            return nil
        }

        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 720, height: 420)

        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)

        guard let snapshot = try? await snapshotter.snapshot else {
            return nil
        }

        return snapshot.image.jpegData(compressionQuality: 0.84)
    }
}
