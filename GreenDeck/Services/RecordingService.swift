import AVFoundation
import CoreImage

/// Writes composited video frames + audio to a single segment file using
/// AVAssetWriter. All append calls must happen on the capture/serial queue.
final class RecordingService {

    enum RecordingError: LocalizedError {
        case writerSetupFailed(String)
        case notRecording

        var errorDescription: String? {
            switch self {
            case .writerSetupFailed(let m): return "Could not start recording: \(m)"
            case .notRecording: return "Not currently recording."
            }
        }
    }

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let ciContext: CIContext
    private var outputSize: CGSize = .zero
    private var sessionStarted = false
    private var startTime: CMTime = .zero
    private var lastVideoTime: CMTime = .zero

    private(set) var isRecording = false
    private(set) var currentFileName: String?

    init(ciContext: CIContext) {
        self.ciContext = ciContext
    }

    // MARK: Lifecycle

    func start(outputSize: CGSize, includeAudio: Bool) throws {
        let fileName = "\(UUID().uuidString).mov"
        let url = FilePaths.segmentsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw RecordingError.writerSetupFailed(error.localizedDescription)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(outputSize.width),
            kCVPixelBufferHeightKey as String: Int(outputSize.height)
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attrs
        )

        guard writer.canAdd(videoInput) else {
            throw RecordingError.writerSetupFailed("cannot add video input")
        }
        writer.add(videoInput)

        if includeAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 96000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                self.audioInput = audioInput
            }
        }

        guard writer.startWriting() else {
            throw RecordingError.writerSetupFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }

        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.outputSize = outputSize
        self.currentFileName = fileName
        self.sessionStarted = false
        self.isRecording = true
        Log.recording.info("Recording started -> \(fileName)")
    }

    /// Append a composited video frame. `time` is the source presentation time.
    func appendVideo(_ image: CIImage, at time: CMTime) {
        guard isRecording, let adaptor, let videoInput else { return }

        if !sessionStarted {
            startTime = time
            writer?.startSession(atSourceTime: time)
            sessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbOut)
        guard let pixelBuffer = pbOut else { return }

        ciContext.render(
            image,
            to: pixelBuffer,
            bounds: CGRect(origin: .zero, size: outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        adaptor.append(pixelBuffer, withPresentationTime: time)
        lastVideoTime = time
    }

    /// Append an audio sample buffer untouched.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    /// Finalize the file. Returns (fileName, duration).
    func stop() async -> (fileName: String, duration: TimeInterval)? {
        guard isRecording, let writer, let fileName = currentFileName else { return nil }
        isRecording = false
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()

        let duration = sessionStarted
            ? CMTimeGetSeconds(CMTimeSubtract(lastVideoTime, startTime))
            : 0

        await writer.finishWriting()

        let result: (String, TimeInterval)?
        if writer.status == .completed {
            Log.recording.info("Recording finished \(fileName) (\(duration)s)")
            result = (fileName, max(0, duration))
        } else {
            Log.recording.error("Recording failed: \(writer.error?.localizedDescription ?? "unknown")")
            result = nil
        }

        self.writer = nil
        self.videoInput = nil
        self.audioInput = nil
        self.adaptor = nil
        self.currentFileName = nil
        self.sessionStarted = false
        return result
    }
}
