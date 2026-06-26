import Foundation
import CoreGraphics

/// How a background image is fitted into the 9:16 output frame.
enum CropMode: String, Codable, CaseIterable, Identifiable {
    case fill       // image fills the frame, excess cropped
    case contain    // whole image visible, letterboxed with black
    case blurFill   // blurred enlarged image fills frame, original centered on top
    case custom     // base fill + user-applied scale/position

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .contain: return "Contain"
        case .blurFill: return "Blur Fill"
        case .custom: return "Custom"
        }
    }
}

/// Vision person-segmentation quality / performance trade-off.
enum SegmentationQuality: String, Codable, CaseIterable, Identifiable {
    case fast       // recording performance mode
    case balanced   // default
    case accurate   // preview-quality, may reduce frame rate

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .accurate: return "Accurate"
        }
    }
}

/// Output resolution of recorded/exported video.
enum OutputResolution: String, Codable, CaseIterable, Identifiable {
    case p720x1280
    case p1080x1920

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .p720x1280: return "720 × 1280"
        case .p1080x1920: return "1080 × 1920"
        }
    }

    var pixelSize: CGSize {
        switch self {
        case .p720x1280: return CGSize(width: 720, height: 1280)
        case .p1080x1920: return CGSize(width: 1080, height: 1920)
        }
    }
}

/// User-configurable app settings. Persisted between launches.
struct AppSettings: Codable {
    /// Any Google Sheets URL (the whole spreadsheet) or a direct CSV URL.
    var spreadsheetURL: URL?
    /// The deck (tab) currently selected for browsing/recording.
    var selectedDeckID: String?
    var defaultCropMode: CropMode
    var segmentationQuality: SegmentationQuality
    var outputResolution: OutputResolution
    var microphoneEnabled: Bool
    var showCaptionOverlay: Bool
    var showPrivateNotesDuringRecording: Bool
    var mirrorPreview: Bool
    var mirrorExport: Bool

    static let `default` = AppSettings(
        spreadsheetURL: nil,
        selectedDeckID: nil,
        defaultCropMode: .fill,
        segmentationQuality: .balanced,
        outputResolution: .p1080x1920,
        microphoneEnabled: true,
        showCaptionOverlay: true,
        showPrivateNotesDuringRecording: false,
        mirrorPreview: true,
        mirrorExport: false
    )

    // Tolerant decoding so adding/removing fields never wipes existing settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        spreadsheetURL = try c.decodeIfPresent(URL.self, forKey: .spreadsheetURL)
        selectedDeckID = try c.decodeIfPresent(String.self, forKey: .selectedDeckID)
        defaultCropMode = try c.decodeIfPresent(CropMode.self, forKey: .defaultCropMode) ?? d.defaultCropMode
        segmentationQuality = try c.decodeIfPresent(SegmentationQuality.self, forKey: .segmentationQuality) ?? d.segmentationQuality
        outputResolution = try c.decodeIfPresent(OutputResolution.self, forKey: .outputResolution) ?? d.outputResolution
        microphoneEnabled = try c.decodeIfPresent(Bool.self, forKey: .microphoneEnabled) ?? d.microphoneEnabled
        showCaptionOverlay = try c.decodeIfPresent(Bool.self, forKey: .showCaptionOverlay) ?? d.showCaptionOverlay
        showPrivateNotesDuringRecording = try c.decodeIfPresent(Bool.self, forKey: .showPrivateNotesDuringRecording) ?? d.showPrivateNotesDuringRecording
        mirrorPreview = try c.decodeIfPresent(Bool.self, forKey: .mirrorPreview) ?? d.mirrorPreview
        mirrorExport = try c.decodeIfPresent(Bool.self, forKey: .mirrorExport) ?? d.mirrorExport
    }

    init(spreadsheetURL: URL?, selectedDeckID: String?, defaultCropMode: CropMode,
         segmentationQuality: SegmentationQuality, outputResolution: OutputResolution,
         microphoneEnabled: Bool, showCaptionOverlay: Bool,
         showPrivateNotesDuringRecording: Bool, mirrorPreview: Bool, mirrorExport: Bool) {
        self.spreadsheetURL = spreadsheetURL
        self.selectedDeckID = selectedDeckID
        self.defaultCropMode = defaultCropMode
        self.segmentationQuality = segmentationQuality
        self.outputResolution = outputResolution
        self.microphoneEnabled = microphoneEnabled
        self.showCaptionOverlay = showCaptionOverlay
        self.showPrivateNotesDuringRecording = showPrivateNotesDuringRecording
        self.mirrorPreview = mirrorPreview
        self.mirrorExport = mirrorExport
    }
}
