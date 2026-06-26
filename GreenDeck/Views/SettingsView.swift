import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var urlText: String = ""
    @State private var showClearConfirm = false
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Google Sheet") {
                TextField("Google Sheets URL", text: $urlText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Save URL") { saveURL() }
                    .disabled(URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
                Text("Paste the whole spreadsheet link (the one in your browser). Each tab becomes a deck. Share it as “Anyone with the link can view.” Tabs named starting with . or _ are ignored.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Recording") {
                Picker("Default crop mode", selection: cropBinding) {
                    ForEach(CropMode.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Segmentation quality", selection: qualityBinding) {
                    ForEach(SegmentationQuality.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Output resolution", selection: resolutionBinding) {
                    ForEach(OutputResolution.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Microphone", isOn: boolBinding(\.microphoneEnabled))
                Toggle("Mirror preview", isOn: boolBinding(\.mirrorPreview))
                Toggle("Mirror exported video", isOn: boolBinding(\.mirrorExport))
                Toggle("Show caption overlay", isOn: boolBinding(\.showCaptionOverlay))
                Toggle("Show notes during recording", isOn: boolBinding(\.showPrivateNotesDuringRecording))
            }

            Section("Maintenance") {
                Button("Clear image cache", role: .destructive) { showClearConfirm = true }
                Button("Reset local statuses", role: .destructive) { showResetConfirm = true }
            }
        }
        .navigationTitle("Settings")
        .onAppear { urlText = state.settings.spreadsheetURL?.absoluteString ?? "" }
        .confirmationDialog("Clear all cached images?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear cache", role: .destructive) { state.clearCache() }
        }
        .confirmationDialog("Reset all statuses to New?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset statuses", role: .destructive) { state.resetStatuses() }
        }
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        state.updateSettings { $0.spreadsheetURL = URL(string: trimmed) }
    }

    private var cropBinding: Binding<CropMode> {
        Binding(get: { state.settings.defaultCropMode },
                set: { v in state.updateSettings { $0.defaultCropMode = v } })
    }
    private var qualityBinding: Binding<SegmentationQuality> {
        Binding(get: { state.settings.segmentationQuality },
                set: { v in state.updateSettings { $0.segmentationQuality = v } })
    }
    private var resolutionBinding: Binding<OutputResolution> {
        Binding(get: { state.settings.outputResolution },
                set: { v in state.updateSettings { $0.outputResolution = v } })
    }
    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.settings[keyPath: keyPath] },
                set: { v in state.updateSettings { $0[keyPath: keyPath] = v } })
    }
}

#Preview {
    NavigationStack { SettingsView().environmentObject(AppState()) }
}
