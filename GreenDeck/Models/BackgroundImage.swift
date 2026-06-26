import Foundation

/// Status of a background within the user's curation workflow.
/// Mirrors the `status` column in the Google Sheet CSV.
enum BackgroundStatus: String, Codable, CaseIterable, Identifiable {
    case new
    case used
    case skipped
    case starred
    case rejected

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .new: return "New"
        case .used: return "Used"
        case .skipped: return "Skipped"
        case .starred: return "Starred"
        case .rejected: return "Rejected"
        }
    }
}

/// Result of attempting to download + decode an image into the local cache.
enum CacheStatus: String, Codable {
    case pending
    case cached
    case failed
}

/// A curated background image, sourced from a row in the Google Sheet CSV
/// and cached locally so recording works fully offline.
struct BackgroundImage: Identifiable, Codable, Hashable {
    var id: String
    /// The deck (spreadsheet tab) this image belongs to. Empty for legacy data.
    var deckID: String
    var title: String
    var imageURL: URL
    var localFileName: String?
    var tags: [String]
    var caption: String?
    var source: String?
    var status: BackgroundStatus
    var priority: Int
    var notes: String?

    // Cache bookkeeping
    var cacheStatus: CacheStatus
    var cacheError: String?

    // Local metadata that must survive re-syncs
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var usedCount: Int

    init(
        id: String,
        deckID: String = "",
        title: String = "",
        imageURL: URL,
        localFileName: String? = nil,
        tags: [String] = [],
        caption: String? = nil,
        source: String? = nil,
        status: BackgroundStatus = .new,
        priority: Int = 0,
        notes: String? = nil,
        cacheStatus: CacheStatus = .pending,
        cacheError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        usedCount: Int = 0
    ) {
        self.id = id
        self.deckID = deckID
        self.title = title
        self.imageURL = imageURL
        self.localFileName = localFileName
        self.tags = tags
        self.caption = caption
        self.source = source
        self.status = status
        self.priority = priority
        self.notes = notes
        self.cacheStatus = cacheStatus
        self.cacheError = cacheError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.usedCount = usedCount
    }

    var isCached: Bool { cacheStatus == .cached && localFileName != nil }

    /// Filesystem-safe base name for the cached file, unique across decks.
    var cacheBaseName: String {
        let raw = deckID.isEmpty ? id : "\(deckID)_\(id)"
        let allowed = CharacterSet.alphanumerics
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }

    /// Absolute URL to the cached image file, if present.
    var localFileURL: URL? {
        guard let localFileName else { return nil }
        return FilePaths.imageCacheDirectory.appendingPathComponent(localFileName)
    }
}
