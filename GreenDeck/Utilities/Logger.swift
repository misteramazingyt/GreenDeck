import Foundation
import os

/// Lightweight logging wrapper over os.Logger with stable subsystem/category.
enum Log {
    private static let subsystem = "com.greendeck.app"

    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let cache = Logger(subsystem: subsystem, category: "cache")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let segmentation = Logger(subsystem: subsystem, category: "segmentation")
    static let recording = Logger(subsystem: subsystem, category: "recording")
    static let export = Logger(subsystem: subsystem, category: "export")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let app = Logger(subsystem: subsystem, category: "app")
}
