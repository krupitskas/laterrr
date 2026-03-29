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
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isConfigured = false
    @Published var lastError: String?

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "Laterrr.camera.session", qos: .userInitiated)
    private var pendingPhotoContinuation: CheckedContinuation<CapturedPhoto, Error>?

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
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() {
        sessionQueue.async {
            guard !self.isConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            defer {
                self.session.commitConfiguration()
            }

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: camera),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                Task { @MainActor in
                    self.lastError = CameraCaptureError.unavailable.localizedDescription
                }
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)

            Task { @MainActor in
                self.isConfigured = true
            }
        }
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
