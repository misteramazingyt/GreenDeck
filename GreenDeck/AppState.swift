import SwiftUI
import CoreImage

/// Central observable store. Owns persisted data + services and exposes
/// high-level actions to the views.
@MainActor
final class AppState: ObservableObject {

    // Persisted data
    @Published var settings: AppSettings
    @Published var backgrounds: [BackgroundImage] = []
    @Published var segments: [RecordingSegment] = []

    // Sync UI state
    @Published var isSyncing = false
    @Published var syncStatus: String = ""
    @Published var lastSyncReport: SyncReport?
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    // Export UI state
    @Published var isExporting = false
    @Published var exportMessage: String?

    // Shared camera pipeline (used by the recorder).
    let camera = CameraService()

    // Services
    private let persistence = PersistenceService()
    private let cache = ImageCacheService()
    private let photoLibrary = PhotoLibraryService()
    private let exporter = ExportService()
    private lazy var sync = SheetSyncService(cache: cache)

    init() {
        let p = PersistenceService()
        self.settings = p.loadSettings()
        self.backgrounds = p.loadBackgrounds()
        self.segments = p.loadSegments()
        camera.apply(settings: settings)
    }

    // MARK: Derived stats

    var cachedCount: Int { backgrounds.filter { $0.isCached }.count }
    var newCount: Int { backgrounds.filter { $0.status == .new }.count }
    var starredCount: Int { backgrounds.filter { $0.status == .starred }.count }
    var usedCount: Int { backgrounds.filter { $0.status == .used }.count }
    var hasSheetURL: Bool { settings.sheetCSVURL != nil }

    // MARK: Settings

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        persistence.saveSettings(settings)
        camera.apply(settings: settings)
    }

    // MARK: Sync

    func syncSheet() async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncStatus = "Starting…"
        defer { isSyncing = false }

        do {
            let (merged, report) = try await sync.sync(
                url: settings.sheetCSVURL,
                existing: backgrounds,
                onProgress: { [weak self] text in
                    Task { @MainActor in self?.syncStatus = text }
                }
            )
            backgrounds = merged.sorted { $0.priority > $1.priority }
            persistence.saveBackgrounds(backgrounds)
            lastSyncReport = report
            lastSyncDate = Date()
            syncStatus = "Done"
        } catch {
            syncError = error.localizedDescription
            syncStatus = "Failed"
        }
    }

    // MARK: Background mutations

    func update(_ background: BackgroundImage) {
        guard let idx = backgrounds.firstIndex(where: { $0.id == background.id }) else { return }
        backgrounds[idx] = background
        persistence.saveBackgrounds(backgrounds)
    }

    func setStatus(_ status: BackgroundStatus, for id: String) {
        guard let idx = backgrounds.firstIndex(where: { $0.id == id }) else { return }
        backgrounds[idx].status = status
        backgrounds[idx].updatedAt = Date()
        persistence.saveBackgrounds(backgrounds)
    }

    func toggleStar(_ id: String) {
        guard let idx = backgrounds.firstIndex(where: { $0.id == id }) else { return }
        backgrounds[idx].status = backgrounds[idx].status == .starred ? .new : .starred
        persistence.saveBackgrounds(backgrounds)
    }

    func markUsed(_ id: String) {
        guard let idx = backgrounds.firstIndex(where: { $0.id == id }) else { return }
        backgrounds[idx].status = .used
        backgrounds[idx].usedCount += 1
        backgrounds[idx].lastUsedAt = Date()
        persistence.saveBackgrounds(backgrounds)
    }

    func clearCache() {
        Task {
            await cache.clearCache()
            await MainActor.run {
                for i in backgrounds.indices {
                    backgrounds[i].cacheStatus = .pending
                    backgrounds[i].localFileName = nil
                }
                persistence.saveBackgrounds(backgrounds)
            }
        }
    }

    func resetStatuses() {
        for i in backgrounds.indices {
            backgrounds[i].status = .new
            backgrounds[i].usedCount = 0
            backgrounds[i].lastUsedAt = nil
        }
        persistence.saveBackgrounds(backgrounds)
    }

    // MARK: Recorder helpers

    var cachedBackgrounds: [BackgroundImage] {
        backgrounds.filter { $0.isCached }
    }

    /// Load the cached image off the main thread and hand it to the camera.
    func selectBackground(_ background: BackgroundImage) {
        let fileName = background.localFileName
        let id = background.id
        Task.detached(priority: .userInitiated) { [camera] in
            let image = ImageCacheService.loadCIImage(fileName: fileName)
            await MainActor.run { camera.setBackground(image, id: id) }
        }
    }

    func appendSegment(_ segment: RecordingSegment) {
        var s = segment
        s.orderIndex = segments.count
        segments.append(s)
        persistence.saveSegments(segments)
        markUsed(segment.backgroundID)
    }

    // MARK: Segment management

    func deleteSegment(_ segment: RecordingSegment) {
        try? FileManager.default.removeItem(at: segment.fileURL)
        segments.removeAll { $0.id == segment.id }
        reindexSegments()
        persistence.saveSegments(segments)
    }

    func moveSegments(from source: IndexSet, to destination: Int) {
        segments.move(fromOffsets: source, toOffset: destination)
        reindexSegments()
        persistence.saveSegments(segments)
    }

    func renameSegment(_ id: UUID, notes: String) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[idx].notes = notes
        persistence.saveSegments(segments)
    }

    private func reindexSegments() {
        for i in segments.indices { segments[i].orderIndex = i }
    }

    // MARK: Export

    func exportAll() async -> URL? {
        guard !isExporting else { return nil }
        isExporting = true
        exportMessage = "Exporting…"
        defer { isExporting = false }
        do {
            let url = try await exporter.export(
                segments: segments,
                outputResolution: settings.outputResolution
            )
            try await photoLibrary.saveVideo(at: url)
            exportMessage = "Saved to Photos."
            return url
        } catch {
            exportMessage = error.localizedDescription
            return nil
        }
    }
}
