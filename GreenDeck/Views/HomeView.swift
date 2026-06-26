import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !state.hasSheetURL {
                        setupPrompt
                    }
                    statusCard
                    actionGrid
                }
                .padding()
            }
            .navigationTitle("GreenDeck")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var setupPrompt: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Label("Add a Google Sheet CSV URL to get started", systemImage: "link.badge.plus")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deck status").font(.headline)
            row("Images synced", "\(state.backgrounds.count)")
            row("Cached", "\(state.cachedCount) / \(state.backgrounds.count)")
            row("New", "\(state.newCount)")
            row("Starred", "\(state.starredCount)")
            row("Used", "\(state.usedCount)")
            if let date = state.lastSyncDate {
                row("Last sync", date.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private var actionGrid: some View {
        VStack(spacing: 12) {
            NavigationLink { SyncView() } label: {
                actionLabel("Sync Sheet", "arrow.triangle.2.circlepath", .blue)
            }
            NavigationLink { DeckView() } label: {
                actionLabel("Open Deck", "square.grid.2x2", .indigo)
            }
            NavigationLink { RecorderView() } label: {
                actionLabel("Record", "record.circle", .red)
            }
            .disabled(state.cachedBackgrounds.isEmpty)

            NavigationLink { SegmentReviewView() } label: {
                actionLabel("Segments (\(state.segments.count))", "film.stack", .green)
            }
        }
    }

    private func actionLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack {
            Image(systemName: icon).font(.title2).frame(width: 32)
            Text(title).fontWeight(.semibold)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.primary)
    }
}

#Preview {
    HomeView().environmentObject(AppState())
}
