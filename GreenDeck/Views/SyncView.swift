import SwiftUI

struct SyncView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !state.hasSheetURL {
                    Text("No CSV URL configured. Add one in Settings.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await state.syncSheet() }
                } label: {
                    HStack {
                        if state.isSyncing { ProgressView().tint(.white) }
                        Text(state.isSyncing ? "Syncing…" : "Sync Sheet")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                }
                .disabled(state.isSyncing || !state.hasSheetURL)

                if state.isSyncing {
                    Text(state.syncStatus).foregroundStyle(.secondary)
                }

                if let error = state.syncError {
                    errorBox(error)
                }

                if let report = state.lastSyncReport {
                    reportBox(report)
                }
            }
            .padding()
        }
        .navigationTitle("Sync")
    }

    private func errorBox(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sync failed", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(message).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func reportBox(_ report: SyncReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last sync").font(.headline)
            Text(report.summary).font(.callout).monospaced()
            if !report.invalidRowMessages.isEmpty {
                DisclosureGroup("Invalid rows (\(report.invalidRowMessages.count))") {
                    ForEach(report.invalidRowMessages, id: \.self) { Text($0).font(.caption) }
                }
            }
            if !report.failedDownloadMessages.isEmpty {
                DisclosureGroup("Failed downloads (\(report.failedDownloadMessages.count))") {
                    ForEach(report.failedDownloadMessages, id: \.self) { Text($0).font(.caption) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack { SyncView().environmentObject(AppState()) }
}
