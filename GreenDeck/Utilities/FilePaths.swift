import Foundation

/// Centralized, lazily-created locations for all on-disk app data.
/// Everything lives under the app's Documents directory so it survives launches.
enum FilePaths {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var imageCacheDirectory: URL {
        ensure(documentsDirectory.appendingPathComponent("ImageCache", isDirectory: true))
    }

    static var segmentsDirectory: URL {
        ensure(documentsDirectory.appendingPathComponent("Segments", isDirectory: true))
    }

    static var exportsDirectory: URL {
        ensure(documentsDirectory.appendingPathComponent("Exports", isDirectory: true))
    }

    static var backgroundsStoreURL: URL {
        documentsDirectory.appendingPathComponent("backgrounds.json")
    }

    static var segmentsStoreURL: URL {
        documentsDirectory.appendingPathComponent("segments.json")
    }

    static var settingsStoreURL: URL {
        documentsDirectory.appendingPathComponent("settings.json")
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// Best-effort total size (bytes) of cached images, for display in UI.
    static func imageCacheSize() -> Int64 {
        directorySize(imageCacheDirectory)
    }

    static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
