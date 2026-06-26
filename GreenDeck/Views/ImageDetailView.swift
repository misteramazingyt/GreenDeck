import SwiftUI

struct ImageDetailView: View {
    @EnvironmentObject private var state: AppState
    let backgroundID: String
    @State private var goToRecorder = false

    private var background: BackgroundImage? {
        state.backgrounds.first { $0.id == backgroundID }
    }

    var body: some View {
        ScrollView {
            if let bg = background {
                VStack(alignment: .leading, spacing: 14) {
                    CachedThumbnail(fileName: bg.localFileName, maxPixel: 1200)
                        .aspectRatio(9.0/16.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(bg.title.isEmpty ? bg.id : bg.title)
                        .font(.title2).bold()

                    if let caption = bg.caption, !caption.isEmpty {
                        Text(caption).foregroundStyle(.secondary)
                    }
                    if let source = bg.source, !source.isEmpty {
                        label("Source", source)
                    }
                    if !bg.tags.isEmpty {
                        label("Tags", bg.tags.joined(separator: ", "))
                    }
                    if let notes = bg.notes, !notes.isEmpty {
                        label("Notes", notes)
                    }
                    label("Status", bg.status.displayName)
                    label("Cache", bg.isCached ? "Cached" : (bg.cacheError ?? "Not cached"))

                    statusControls(bg)

                    Button {
                        state.selectBackground(bg)
                        goToRecorder = true
                    } label: {
                        Label("Use in Recorder", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(bg.isCached ? Color.red : Color.gray,
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .disabled(!bg.isCached)
                }
                .padding()
            } else {
                Text("Image not found.").foregroundStyle(.secondary).padding()
            }
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToRecorder) { RecorderView() }
    }

    private func label(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func statusControls(_ bg: BackgroundImage) -> some View {
        Picker("Status", selection: Binding(
            get: { bg.status },
            set: { state.setStatus($0, for: bg.id) }
        )) {
            ForEach(BackgroundStatus.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
