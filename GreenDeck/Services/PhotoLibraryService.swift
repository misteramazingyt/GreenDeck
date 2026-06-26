import Photos

/// Saves exported videos to the user's Photos library (add-only permission).
struct PhotoLibraryService {

    enum SaveError: LocalizedError {
        case permissionDenied
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Photos access is off. Enable it in Settings → Privacy & Security → Photos → GreenDeck."
            case .saveFailed(let m):
                return "Could not save to Photos: \(m)"
            }
        }
    }

    func saveVideo(at url: URL) async throws {
        guard await Permissions.requestPhotosAdd() else {
            throw SaveError.permissionDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            Log.export.info("Saved export to Photos")
        } catch {
            throw SaveError.saveFailed(error.localizedDescription)
        }
    }
}
