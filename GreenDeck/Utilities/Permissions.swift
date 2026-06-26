import AVFoundation
import Photos

/// Thin async wrappers around the system permission prompts the app needs.
enum Permissions {

    enum State {
        case authorized
        case denied
        case notDetermined

        var isAuthorized: Bool { self == .authorized }
    }

    // MARK: Camera

    static var cameraState: State {
        map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    @discardableResult
    static func requestCamera() async -> Bool {
        if cameraState == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: Microphone

    static var microphoneState: State {
        map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    @discardableResult
    static func requestMicrophone() async -> Bool {
        if microphoneState == .authorized { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: Photo library (add-only)

    static var photosAddState: State {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    @discardableResult
    static func requestPhotosAdd() async -> Bool {
        if photosAddState == .authorized { return true }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    // MARK: Helpers

    private static func map(_ status: AVAuthorizationStatus) -> State {
        switch status {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
