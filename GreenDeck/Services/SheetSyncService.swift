import Foundation

/// A human-readable report produced by a sync run.
struct SyncReport {
    var rowsFound = 0
    var newImages = 0
    var updatedImages = 0
    var imagesCached = 0
    var failedDownloads = 0
    var invalidRows = 0
    var invalidRowMessages: [String] = []
    var failedDownloadMessages: [String] = []

    var summary: String {
        """
        Rows found: \(rowsFound)
        New images added: \(newImages)
        Existing images updated: \(updatedImages)
        Images cached: \(imagesCached)
        Failed downloads: \(failedDownloads)
        Invalid rows: \(invalidRows)
        """
    }
}

enum SyncError: LocalizedError {
    case noURL
    case downloadFailed(String)
    case emptyOrInvalid

    var errorDescription: String? {
        switch self {
        case .noURL: return "No Google Sheet CSV URL is configured. Add one in Settings."
        case .downloadFailed(let m): return "Could not download the CSV: \(m)"
        case .emptyOrInvalid: return "The CSV had no valid image rows. Check the URL and columns."
        }
    }
}

/// Fetches the published CSV, parses + validates rows, merges with the local
/// database (preserving local status/usage), and caches missing images.
struct SheetSyncService {

    let cache: ImageCacheService

    /// Performs a full sync. `existing` is the current local set; the returned
    /// array is the merged result. Progress is reported via `onProgress`.
    func sync(
        url: URL?,
        existing: [BackgroundImage],
        onProgress: @escaping (String) -> Void = { _ in }
    ) async throws -> (merged: [BackgroundImage], report: SyncReport) {
        guard let url else { throw SyncError.noURL }

        onProgress("Downloading CSV…")
        let text = try await downloadCSV(url)

        onProgress("Parsing rows…")
        let rows = CSVParser.parse(text)
        var report = SyncReport()
        report.rowsFound = rows.count

        var byID: [String: BackgroundImage] = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, $0) }
        )
        var seenIDs = Set<String>()

        for row in rows {
            switch makeBackground(from: row, existing: byID) {
            case .failure(let message):
                report.invalidRows += 1
                report.invalidRowMessages.append(message)
            case .success(let bg):
                if seenIDs.contains(bg.id) {
                    report.invalidRows += 1
                    report.invalidRowMessages.append("Duplicate id: \(bg.id)")
                    continue
                }
                seenIDs.insert(bg.id)
                if byID[bg.id] == nil {
                    report.newImages += 1
                } else {
                    report.updatedImages += 1
                }
                byID[bg.id] = bg
            }
        }

        guard !seenIDs.isEmpty else { throw SyncError.emptyOrInvalid }

        // Download any images not yet cached.
        var merged = Array(byID.values)
        for index in merged.indices {
            var bg = merged[index]
            let alreadyCached = await cache.isCached(fileName: bg.localFileName)
            if alreadyCached && bg.cacheStatus == .cached { continue }
            onProgress("Caching \(bg.title.isEmpty ? bg.id : bg.title)…")
            do {
                let fileName = try await cache.cache(bg)
                bg.localFileName = fileName
                bg.cacheStatus = .cached
                bg.cacheError = nil
                report.imagesCached += 1
            } catch {
                bg.cacheStatus = .failed
                bg.cacheError = error.localizedDescription
                report.failedDownloads += 1
                report.failedDownloadMessages.append("\(bg.id): \(error.localizedDescription)")
            }
            merged[index] = bg
        }

        merged.sort { $0.priority > $1.priority }
        return (merged, report)
    }

    // MARK: Row -> Model

    private func makeBackground(
        from row: [String: String],
        existing: [String: BackgroundImage]
    ) -> Result<BackgroundImage, String> {
        let urlString = (row["image_url"] ?? "").trimmingCharacters(in: .whitespaces)
        guard !urlString.isEmpty, let imageURL = URL(string: urlString) else {
            return .failure("Missing or invalid image_url")
        }

        var id = (row["id"] ?? "").trimmingCharacters(in: .whitespaces)
        if id.isEmpty {
            // Generate a stable id from the URL, but this is flagged as a warning case.
            id = String(urlString.hashValue, radix: 16)
        }

        let tags = (row["tags"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let statusRaw = (row["status"] ?? "")
            .replacingOccurrences(of: "status:", with: "")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let sheetStatus = BackgroundStatus(rawValue: statusRaw)

        let priority = Int((row["priority"] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0

        if let prior = existing[id] {
            // Preserve local workflow state; refresh metadata from the sheet.
            var bg = prior
            bg.title = row["title"] ?? bg.title
            bg.imageURL = imageURL
            bg.tags = tags
            bg.caption = row["caption"]
            bg.source = row["source"]
            bg.priority = priority
            bg.notes = row["notes"]
            bg.updatedAt = Date()
            // Only adopt a sheet status if the local one is still the default `new`.
            if bg.status == .new, let sheetStatus { bg.status = sheetStatus }
            // If the remote URL changed, force a re-cache.
            if prior.imageURL != imageURL { bg.cacheStatus = .pending; bg.localFileName = nil }
            return .success(bg)
        }

        let bg = BackgroundImage(
            id: id,
            title: row["title"] ?? "",
            imageURL: imageURL,
            tags: tags,
            caption: row["caption"],
            source: row["source"],
            status: sheetStatus ?? .new,
            priority: priority,
            notes: row["notes"]
        )
        return .success(bg)
    }

    private func downloadCSV(_ url: URL) async throws -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SyncError.downloadFailed("HTTP \(http.statusCode)")
            }
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw SyncError.downloadFailed("Could not decode CSV text")
            }
            return text
        } catch let e as SyncError {
            throw e
        } catch {
            throw SyncError.downloadFailed(error.localizedDescription)
        }
    }
}
