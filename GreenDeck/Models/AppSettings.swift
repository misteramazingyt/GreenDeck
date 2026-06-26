import Foundation
import CoreGraphics

/// How a background image is fitted into the 9:16 output frame.
enum CropMode: String, Codable, CaseIterable, Identifiable {
    case fill       // image fills the frame, excess cropped
    case contain    // whole image visible, letterboxed with black
    case blurFill   // blurred enlarged image fills frame, original centered on top

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .contain: return "Contain"
        case .blurFill: return "Blur Fill"
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
    var sheetCSVURL: URL?
    var defaultCropMode: CropMode
    var segmentationQuality: SegmentationQuality
    var outputResolution: OutputResolution
    var microphoneEnabled: Bool
    var showCaptionOverlay: Bool
    var showPrivateNotesDuringRecording: Bool
    var mirrorPreview: Bool
    var mirrorExport: Bool

    static let `default` = AppSettings(
        sheetCSVURL: nil,
        defaultCropMode: .fill,
        segmentationQuality: .balanced,
        outputResolution: .p1080x1920,
        microphoneEnabled: true,
        showCaptionOverlay: true,
        showPrivateNotesDuringRecording: false,
        mirrorPreview: true,
        mirrorExport: false
    )
}
