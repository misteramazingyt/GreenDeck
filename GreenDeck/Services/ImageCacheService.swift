import UIKit
import CoreImage

/// Downloads remote images, stores them locally, and loads them back for
/// thumbnails and full-resolution compositing. Network is only touched here,
/// during sync — never during recording.
actor ImageCacheService {

    enum CacheError: LocalizedError {
        case downloadFailed(String)
        case decodeFailed
        case tooSmall(Int)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let msg): return "Download failed: \(msg)"
            case .decodeFailed: return "Image could not be decoded."
            case .tooSmall(let dim): return "Image too small (\(dim)px)."
            }
        }
    }

    private let minimumDimension = 360
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    /// Download + validate an image, writing it into the cache directory.
    /// Returns the local file name on success.
    func cache(_ background: BackgroundImage) async throws -> String {
        let (data, response) = try await download(Self.normalize(background.imageURL))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CacheError.downloadFailed("HTTP \(code)")
        }
        guard let image = UIImage(data: data) else {
            throw CacheError.decodeFailed
        }
        let minDim = Int(min(image.size.width, image.size.height) * image.scale)
        if minDim < minimumDimension {
            throw CacheError.tooSmall(minDim)
        }

        let ext = preferredExtension(for: background.imageURL, data: data)
        let fileName = "\(background.cacheBaseName).\(ext)"
        let url = FilePaths.imageCacheDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        Log.cache.info("Cached \(background.id) -> \(fileName)")
        return fileName
    }

    func isCached(fileName: String?) -> Bool {
        guard let fileName else { return false }
        let url = FilePaths.imageCacheDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    func clearCache() {
        let dir = FilePaths.imageCacheDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in contents { try? FileManager.default.removeItem(at: url) }
        }
        Log.cache.info("Image cache cleared")
    }

    // MARK: Loading (nonisolated — pure disk reads)

    /// Load a downsampled thumbnail efficiently using ImageIO.
    nonisolated static func loadThumbnail(fileName: String?, maxPixel: CGFloat = 400) -> UIImage? {
        guard let fileName else { return nil }
        let url = FilePaths.imageCacheDirectory.appendingPathComponent(fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Load the full-resolution background as a CIImage (with orientation applied),
    /// for compositing in the recorder.
    nonisolated static func loadCIImage(fileName: String?) -> CIImage? {
        guard let fileName else { return nil }
        let url = FilePaths.imageCacheDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let ui = UIImage(data: data) else { return nil }
        guard let cg = ui.cgImage else { return nil }
        return CIImage(cgImage: cg)
    }

    // MARK: Helpers

    /// Rewrite common Google Drive share links to a direct-download endpoint
    /// so URLSession receives image bytes instead of an HTML viewer page.
    static func normalize(_ url: URL) -> URL {
        let s = url.absoluteString
        guard s.contains("drive.google.com") else { return url }
        // Extract the file id from /file/d/{id}/, ?id={id}, or /d/{id}.
        let patterns = [#"/file/d/([A-Za-z0-9_-]+)"#, #"[?&]id=([A-Za-z0-9_-]+)"#, #"/d/([A-Za-z0-9_-]+)"#]
        for p in patterns {
            if let r = s.range(of: p, options: .regularExpression) {
                let frag = String(s[r])
                if let idRange = frag.range(of: #"[A-Za-z0-9_-]+$"#, options: .regularExpression) {
                    let id = String(frag[idRange])
                    return URL(string: "https://drive.google.com/uc?export=download&id=\(id)") ?? url
                }
            }
        }
        return url
    }

    private func download(_ url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw CacheError.downloadFailed(error.localizedDescription)
        }
    }

    private func preferredExtension(for url: URL, data: Data) -> String {
        let pathExt = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "webp"].contains(pathExt) {
            return pathExt == "jpeg" ? "jpg" : pathExt
        }
        // Sniff magic bytes for the common formats.
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        return "jpg"
    }
}
