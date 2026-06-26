import Foundation

/// Records a background change that happened during an active recording.
/// For MVP export this is metadata only (the composited output is flat video),
/// but it is preserved for history/debugging.
struct BackgroundChangeEvent: Codable, Hashable {
    var timeOffset: TimeInterval
    var backgroundID: String
}

/// A single recorded clip. Each Record/Stop cycle produces one segment file.
struct RecordingSegment: Identifiable, Codable, Hashable {
    var id: UUID
    var backgroundID: String
    var fileName: String
    var duration: TimeInterval
    var createdAt: Date
    var orderIndex: Int
    var notes: String?
    var backgroundChangeEvents: [BackgroundChangeEvent]

    init(
        id: UUID = UUID(),
        backgroundID: String,
        fileName: String,
        duration: TimeInterval = 0,
        createdAt: Date = Date(),
        orderIndex: Int = 0,
        notes: String? = nil,
        backgroundChangeEvents: [BackgroundChangeEvent] = []
    ) {
        self.id = id
        self.backgroundID = backgroundID
        self.fileName = fileName
        self.duration = duration
        self.createdAt = createdAt
        self.orderIndex = orderIndex
        self.notes = notes
        self.backgroundChangeEvents = backgroundChangeEvents
    }

    /// Absolute URL to the segment's video file on disk.
    var fileURL: URL {
        FilePaths.segmentsDirectory.appendingPathComponent(fileName)
    }
}
