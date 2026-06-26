import AVFoundation
import CoreImage
import UIKit

/// Anything that can display composited preview frames (e.g. the Metal view).
protocol PreviewSink: AnyObject {
    func sendPreview(_ image: CIImage)
}

/// Orchestrates the live pipeline: front-camera + mic capture → Vision
/// segmentation → Core Image compositing → preview + (optional) recording.
///
/// Published properties are updated on the main thread for SwiftUI. Capture
/// callbacks run on `sessionQueue`; shared mutable state is guarded by `lock`.
final class CameraService: NSObject, ObservableObject,
                           AVCaptureVideoDataOutputSampleBufferDelegate,
                           AVCaptureAudioDataOutputSampleBufferDelegate {

    // MARK: Published UI state
    @Published private(set) var isRunning = false
    @Published private(set) var isRecording = false
    @Published private(set) var recordingSeconds: TimeInterval = 0
    @Published var errorMessage: String?
    @Published private(set) var currentBackgroundID: String?

    // MARK: Pipeline collaborators
    private let segmentation = SegmentationService()
    private let compositor = Compositor()
    private let ciContext: CIContext
    private let recorder: RecordingService

    weak var previewSink: PreviewSink?

    override init() {
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        self.ciContext = ctx
        self.recorder = RecordingService(ciContext: ctx)
        super.init()
    }

    // MARK: Capture
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.greendeck.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    // MARK: Shared state (lock-guarded)
    private let lock = NSLock()
    private var backgroundImage: CIImage?
    private var outputSize = OutputResolution.p1080x1920.pixelSize
    private var cropMode: CropMode = .fill
    private var mirrorPreview = true
    private var quality: SegmentationQuality = .balanced
    private var segmentationEnabled = true

    // Recording bookkeeping
    private var recordingStartTime: CMTime?
    private var pendingChangeEvents: [BackgroundChangeEvent] = []
    private var durationTimer: Timer?

    // MARK: Configuration

    func apply(settings: AppSettings) {
        lock.lock()
        outputSize = settings.outputResolution.pixelSize
        cropMode = settings.defaultCropMode
        mirrorPreview = settings.mirrorPreview
        quality = settings.segmentationQuality
        lock.unlock()
        segmentation.quality = settings.segmentationQuality
    }

    func setSegmentationEnabled(_ enabled: Bool) {
        lock.lock(); segmentationEnabled = enabled; lock.unlock()
    }

    func setMirror(_ mirror: Bool) {
        lock.lock(); mirrorPreview = mirror; lock.unlock()
    }

    /// Set the active background. Pass the already-decoded CIImage and its id.
    func setBackground(_ image: CIImage?, id: String?) {
        lock.lock()
        backgroundImage = image
        let recording = recorder.isRecording
        if recording, let id, let start = recordingStartTime {
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let offset = CMTimeGetSeconds(CMTimeSubtract(now, start))
            pendingChangeEvents.append(BackgroundChangeEvent(timeOffset: max(0, offset), backgroundID: id))
        }
        lock.unlock()
        DispatchQueue.main.async { self.currentBackgroundID = id }
    }

    // MARK: Session lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { return }
            self.configureSessionIfNeeded()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private var sessionConfigured = false
    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        // Front camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        } else {
            reportError("Front camera is unavailable.")
        }

        // Microphone
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micInput) {
            session.addInput(micInput)
        }

        // Video output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // Audio output
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(audioOutput) { session.addOutput(audioOutput) }

        // Portrait orientation, front mirroring handled in compositor.
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            connection.isVideoMirrored = false
        }

        session.commitConfiguration()
        sessionConfigured = true
    }

    // MARK: Recording control

    func startRecording(includeAudio: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, !self.recorder.isRecording else { return }
            self.lock.lock()
            let size = self.outputSize
            self.pendingChangeEvents = []
            if let id = self.currentBackgroundIDUnsafe() {
                self.pendingChangeEvents.append(BackgroundChangeEvent(timeOffset: 0, backgroundID: id))
            }
            self.lock.unlock()
            do {
                try self.recorder.start(outputSize: size, includeAudio: includeAudio)
                self.recordingStartTime = nil
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.recordingSeconds = 0
                    self.startDurationTimer()
                }
            } catch {
                self.reportError(error.localizedDescription)
            }
        }
    }

    /// Stops recording. The completion is called on the main thread with the
    /// finalized segment metadata (or nil on failure).
    func stopRecording(backgroundID: String, completion: @escaping (RecordingSegment?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { completion(nil); return }
            let events = self.lockedChangeEvents()
            Task {
                let result = await self.recorder.stop()
                self.recordingStartTime = nil
                await MainActor.run {
                    self.isRecording = false
                    self.stopDurationTimer()
                    guard let result else { completion(nil); return }
                    let segment = RecordingSegment(
                        backgroundID: backgroundID,
                        fileName: result.fileName,
                        duration: result.duration,
                        backgroundChangeEvents: events
                    )
                    completion(segment)
                }
            }
        }
    }

    private func lockedChangeEvents() -> [BackgroundChangeEvent] {
        lock.lock(); defer { lock.unlock() }
        return pendingChangeEvents
    }

    private func currentBackgroundIDUnsafe() -> String? {
        // Assumes lock held by caller.
        return currentBackgroundID
    }

    // MARK: Sample buffer delegates

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if output === audioOutput {
            recorder.appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lock.lock()
        let bg = backgroundImage
        let size = outputSize
        let crop = cropMode
        let mirror = mirrorPreview
        let useSegmentation = segmentationEnabled
        lock.unlock()

        let camera = CIImage(cvPixelBuffer: pixelBuffer)
        let mask = useSegmentation ? segmentation.mask(for: pixelBuffer) : nil

        let composited = compositor.composite(
            camera: camera,
            maskBuffer: mask,
            background: bg,
            outputSize: size,
            cropMode: crop,
            mirror: mirror
        )

        previewSink?.sendPreview(composited)

        if recorder.isRecording {
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if recordingStartTime == nil { recordingStartTime = time }
            recorder.appendVideo(composited, at: time)
        }
    }

    // MARK: Duration timer

    private func startDurationTimer() {
        durationTimer?.invalidate()
        let start = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.recordingSeconds = Date().timeIntervalSince(start)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    // MARK: Errors

    private func reportError(_ message: String) {
        Log.camera.error("\(message)")
        DispatchQueue.main.async { self.errorMessage = message }
    }
}
