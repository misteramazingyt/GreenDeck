import SwiftUI
import AVKit

struct SegmentReviewView: View {
    @EnvironmentObject private var state: AppState
    @State private var editMode: EditMode = .inactive
    @State private var player: AVPlayer?
    @State private var selected: RecordingSegment?

    var body: some View {
        List {
            if state.segments.isEmpty {
                ContentUnavailableView("No segments yet",
                                       systemImage: "film",
                                       description: Text("Record a clip to see it here."))
            } else {
                ForEach(state.segments) { segment in
                    row(segment)
                }
                .onDelete { offsets in
                    offsets.map { state.segments[$0] }.forEach(state.deleteSegment)
                }
                .onMove { state.moveSegments(from: $0, to: $1) }
            }
        }
        .navigationTitle("Segments")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .safeAreaInset(edge: .bottom) {
            if !state.segments.isEmpty { exportBar }
        }
        .sheet(item: $selected, onDismiss: stop) { segment in
            playerSheet(segment)
        }
    }

    private func row(_ segment: RecordingSegment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                CachedThumbnail(fileName: backgroundFileName(segment.backgroundID))
                    .frame(width: 54, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Segment \(segment.orderIndex + 1)").fontWeight(.medium)
                Text(String(format: "%.1fs", segment.duration))
                    .font(.caption).foregroundStyle(.secondary)
                if segment.backgroundChangeEvents.count > 1 {
                    Text("\(segment.backgroundChangeEvents.count) backgrounds")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { selected = segment }
    }

    private func playerSheet(_ segment: RecordingSegment) -> some View {
        Group {
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
            let p = AVPlayer(url: segment.fileURL)
            player = p
            p.play()
        }
    }

    private var exportBar: some View {
        VStack(spacing: 8) {
            if let message = state.exportMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Button {
                Task { _ = await state.exportAll() }
            } label: {
                HStack {
                    if state.isExporting { ProgressView().tint(.white) }
                    Text(state.isExporting ? "Exporting…" : "Export & Save to Photos")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.green, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .disabled(state.isExporting)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func backgroundFileName(_ id: String) -> String? {
        state.backgrounds.first { $0.id == id }?.localFileName
    }

    private func stop() {
        player?.pause()
        player = nil
    }
}

#Preview {
    NavigationStack { SegmentReviewView().environmentObject(AppState()) }
}
