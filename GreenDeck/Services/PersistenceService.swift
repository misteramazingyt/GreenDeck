import Foundation

/// Loads and saves the app's Codable state as JSON files in Documents.
/// Deliberately simple — chosen over SwiftData for MVP predictability.
struct PersistenceService {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Backgrounds

    func loadBackgrounds() -> [BackgroundImage] {
        load([BackgroundImage].self, from: FilePaths.backgroundsStoreURL) ?? []
    }

    func saveBackgrounds(_ items: [BackgroundImage]) {
        save(items, to: FilePaths.backgroundsStoreURL)
    }

    // MARK: Decks

    func loadDecks() -> [Deck] {
        load([Deck].self, from: FilePaths.decksStoreURL) ?? []
    }

    func saveDecks(_ items: [Deck]) {
        save(items, to: FilePaths.decksStoreURL)
    }

    // MARK: Segments

    func loadSegments() -> [RecordingSegment] {
        load([RecordingSegment].self, from: FilePaths.segmentsStoreURL) ?? []
    }

    func saveSegments(_ items: [RecordingSegment]) {
        save(items, to: FilePaths.segmentsStoreURL)
    }

    // MARK: Settings

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: FilePaths.settingsStoreURL) ?? .default
    }

    func saveSettings(_ settings: AppSettings) {
        save(settings, to: FilePaths.settingsStoreURL)
    }

    // MARK: Generic IO

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.persistence.error("Decode failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.persistence.error("Encode/write failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
