import Vision
import CoreVideo

/// Runs Apple's Vision person-segmentation on camera frames and returns a
/// single-channel mask pixel buffer. Quality is tunable for performance.
final class SegmentationService {

    private let request = VNGeneratePersonSegmentationRequest()
    private let sequenceHandler = VNSequenceRequestHandler()

    var quality: SegmentationQuality = .balanced {
        didSet { request.qualityLevel = Self.map(quality) }
    }

    init() {
        request.qualityLevel = Self.map(.balanced)
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    /// Returns a mask pixel buffer for the person detected in `pixelBuffer`,
    /// or nil if segmentation failed / found no person.
    func mask(for pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> CVPixelBuffer? {
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: orientation)
            return request.results?.first?.pixelBuffer
        } catch {
            Log.segmentation.error("Segmentation failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func map(_ q: SegmentationQuality) -> VNGeneratePersonSegmentationRequest.QualityLevel {
        switch q {
        case .fast: return .fast
        case .balanced: return .balanced
        case .accurate: return .accurate
        }
    }
}
