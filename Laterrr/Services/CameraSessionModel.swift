@preconcurrency import AVFoundation
import UIKit

struct CapturedPhoto {
    let image: UIImage
    let data: Data
}

enum CameraCaptureError: LocalizedError {
    case unavailable
    case denied
    case invalidData
    case alreadyCapturing

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The back camera is unavailable on this device."
        case .denied:
            return "Camera access is off. Enable it in Settings to capture storefronts live."
        case .invalidData:
            return "Laterrr could not decode the captured photo."
        case .alreadyCapturing:
            return "A capture is already in progress."
        }
    }
}

@MainActor
final class CameraSessionModel: NSObject, ObservableObject {
    nonisolated private static let defaultDisplayZoomFactor: CGFloat = 2

    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isConfigured = false
    @Published private(set) var displayZoomFactor: CGFloat = 1
    @Published private(set) var minDisplayZoomFactor: CGFloat = 1
    @Published private(set) var maxDisplayZoomFactor: CGFloat = 1
    @Published private(set) var supportsQuietCapture = false
    @Published var lastError: String?

    nonisolated(unsafe) let session = AVCaptureSession()

    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "Laterrr.camera.session", qos: .userInitiated)
    private var pendingPhotoContinuation: CheckedContinuation<CapturedPhoto, Error>?
    nonisolated(unsafe) private var cameraDevice: AVCaptureDevice?
    nonisolated(unsafe) private var displayZoomMultiplier: CGFloat = 1

    var canZoom: Bool {
        maxDisplayZoomFactor > minDisplayZoomFactor + 0.05
    }

    func prepare() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            configureIfNeeded()
            startRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted {
                        self.configureIfNeeded()
                        self.startRunning()
                    } else {
                        self.lastError = CameraCaptureError.denied.localizedDescription
                    }
                }
            }
        default:
            lastError = CameraCaptureError.denied.localizedDescription
        }
    }

    func startRunning() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stopRunning() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capturePhoto() async throws -> CapturedPhoto {
        guard authorizationStatus == .authorized else {
            throw CameraCaptureError.denied
        }

        if pendingPhotoContinuation != nil {
            throw CameraCaptureError.alreadyCapturing
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingPhotoContinuation = continuation

            sessionQueue.async { [photoOutput] in
                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                if #available(iOS 18.0, *), photoOutput.isShutterSoundSuppressionSupported {
                    settings.isShutterSoundSuppressionEnabled = true
                }
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func setDisplayZoomFactor(_ requestedDisplayZoomFactor: CGFloat) {
        sessionQueue.async {
            guard let cameraDevice = self.cameraDevice else { return }

            let multiplier = max(self.displayZoomMultiplier, 0.01)
            let displayRange = self.allowedDisplayZoomRange(for: cameraDevice, multiplier: multiplier)
            let clampedDisplayZoomFactor = min(
                max(requestedDisplayZoomFactor, displayRange.lowerBound),
                displayRange.upperBound
            )
            let actualZoomFactor = min(
                max(clampedDisplayZoomFactor / multiplier, cameraDevice.minAvailableVideoZoomFactor),
                cameraDevice.maxAvailableVideoZoomFactor
            )

            do {
                try cameraDevice.lockForConfiguration()
                cameraDevice.videoZoomFactor = actualZoomFactor
                cameraDevice.unlockForConfiguration()

                Task { @MainActor in
                    self.displayZoomFactor = actualZoomFactor * multiplier
                }
            } catch {
                Task { @MainActor in
                    self.lastError = "Laterrr could not change the camera zoom right now."
                }
            }
        }
    }

    private func configureIfNeeded() {
        sessionQueue.async {
            guard self.cameraDevice == nil else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            defer {
                self.session.commitConfiguration()
            }

            guard
                let camera = self.preferredBackCamera(),
                let input = try? AVCaptureDeviceInput(device: camera),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                Task { @MainActor in
                    self.lastError = CameraCaptureError.unavailable.localizedDescription
                }
                return
            }

            self.cameraDevice = camera
            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)

            let multiplier: CGFloat
            if #available(iOS 18.0, *) {
                multiplier = max(camera.displayVideoZoomFactorMultiplier, 0.01)
            } else {
                multiplier = 1
            }
            self.displayZoomMultiplier = multiplier

            let displayRange = self.allowedDisplayZoomRange(for: camera, multiplier: multiplier)
            let defaultDisplayZoomFactor = min(
                max(Self.defaultDisplayZoomFactor, displayRange.lowerBound),
                displayRange.upperBound
            )
            let defaultActualZoomFactor = min(
                max(defaultDisplayZoomFactor / multiplier, camera.minAvailableVideoZoomFactor),
                camera.maxAvailableVideoZoomFactor
            )

            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = defaultActualZoomFactor
                camera.unlockForConfiguration()
            } catch {
                Task { @MainActor in
                    self.lastError = "Laterrr could not set the default camera zoom."
                }
            }

            Task { @MainActor in
                self.displayZoomFactor = camera.videoZoomFactor * multiplier
                self.minDisplayZoomFactor = displayRange.lowerBound
                self.maxDisplayZoomFactor = displayRange.upperBound
                if #available(iOS 18.0, *) {
                    self.supportsQuietCapture = self.photoOutput.isShutterSoundSuppressionSupported
                } else {
                    self.supportsQuietCapture = false
                }
                self.isConfigured = true
            }
        }
    }

    nonisolated private func preferredBackCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]

        for deviceType in deviceTypes {
            if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
                return device
            }
        }

        return nil
    }

    nonisolated private func allowedDisplayZoomRange(
        for camera: AVCaptureDevice,
        multiplier: CGFloat
    ) -> ClosedRange<CGFloat> {
        let minDisplayZoom = camera.minAvailableVideoZoomFactor * multiplier
        let rawMaxDisplayZoom = camera.maxAvailableVideoZoomFactor * multiplier
        let cappedMaxDisplayZoom = min(rawMaxDisplayZoom, 8)
        return minDisplayZoom...max(minDisplayZoom, cappedMaxDisplayZoom)
    }
}

extension CameraSessionModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            Task { @MainActor in
                pendingPhotoContinuation?.resume(throwing: error)
                pendingPhotoContinuation = nil
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in
                pendingPhotoContinuation?.resume(throwing: CameraCaptureError.invalidData)
                pendingPhotoContinuation = nil
            }
            return
        }

        Task { @MainActor in
            guard let image = UIImage(data: data) else {
                pendingPhotoContinuation?.resume(throwing: CameraCaptureError.invalidData)
                pendingPhotoContinuation = nil
                return
            }

            pendingPhotoContinuation?.resume(returning: CapturedPhoto(image: image, data: data))
            pendingPhotoContinuation = nil
        }
    }
}
