import AVFoundation
import CoreMedia

/// Combines ordered recording segments into a single vertical MP4.
struct ExportService {

    enum ExportError: LocalizedError {
        case noSegments
        case noVideoTrack
        case exportFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noSegments: return "There are no segments to export."
            case .noVideoTrack: return "A segment had no video track."
            case .exportFailed(let m): return "Export failed: \(m)"
            case .cancelled: return "Export was cancelled."
            }
        }
    }

    /// Build and export the final video. Returns the output file URL.
    func export(
        segments: [RecordingSegment],
        outputResolution: OutputResolution
    ) async throws -> URL {
        let ordered = segments.sorted { $0.orderIndex < $1.orderIndex }
        guard !ordered.isEmpty else { throw ExportError.noSegments }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.noVideoTrack
        }

        let renderSize = outputResolution.pixelSize
        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []

        for segment in ordered {
            let asset = AVURLAsset(url: segment.fileURL)
            guard let assetVideo = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let duration = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: duration)

            try videoTrack.insertTimeRange(range, of: assetVideo, at: cursor)
            if let assetAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(range, of: assetAudio, at: cursor)
            }

            // Scale this segment to the render size.
            let naturalSize = try await assetVideo.load(.naturalSize)
            let preferred = try await assetVideo.load(.preferredTransform)
            let transformed = naturalSize.applying(preferred)
            let w = abs(transformed.width), h = abs(transformed.height)
            let scale = max(renderSize.width / max(w, 1), renderSize.height / max(h, 1))

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
            var t = preferred.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            let scaledW = w * scale, scaledH = h * scale
            t = t.concatenating(CGAffineTransform(
                translationX: (renderSize.width - scaledW) / 2,
                y: (renderSize.height - scaledH) / 2))
            layer.setTransform(t, at: cursor)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)

            cursor = CMTimeAdd(cursor, duration)
        }

        guard cursor > .zero else { throw ExportError.noVideoTrack }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        let outputURL = FilePaths.exportsDirectory
            .appendingPathComponent("GreenDeck-\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed("Could not create exporter")
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = videoComposition
        exporter.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously { continuation.resume() }
        }

        switch exporter.status {
        case .completed:
            Log.export.info("Export completed: \(outputURL.lastPathComponent)")
            return outputURL
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportFailed(exporter.error?.localizedDescription ?? "unknown")
        }
    }
}
