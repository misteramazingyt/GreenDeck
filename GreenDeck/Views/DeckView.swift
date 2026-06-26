import SwiftUI

private enum DeckFilter: String, CaseIterable, Identifiable {
    case all, new, starred, used, skipped
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private enum DeckSort: String, CaseIterable, Identifiable {
    case priority, title, recentlyUsed, sheetOrder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .priority: return "Priority"
        case .title: return "Title"
        case .recentlyUsed: return "Recently used"
        case .sheetOrder: return "Sheet order"
        }
    }
}

struct DeckView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @State private var filter: DeckFilter = .all
    @State private var sort: DeckSort = .priority

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filtered) { bg in
                        NavigationLink {
                            ImageDetailView(backgroundID: bg.id)
                        } label: {
                            card(bg)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(bg.status == .starred ? "Unstar" : "Star") { state.toggleStar(bg.id) }
                            Button("Mark skipped") { state.setStatus(.skipped, for: bg.id) }
                            Button("Mark used") { state.markUsed(bg.id) }
                        }
                    }
                }
                .padding(10)
            }
        }
        .navigationTitle(state.selectedDeck?.name ?? "Deck")
        .searchable(text: $search, prompt: "Search title, tags, notes")
        .toolbar {
            if state.decks.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(state.decks) { deck in
                            Button {
                                state.selectDeck(deck)
                            } label: {
                                if deck.id == state.selectedDeck?.id {
                                    Label(deck.name, systemImage: "checkmark")
                                } else {
                                    Text(deck.name)
                                }
                            }
                        }
                    } label: { Image(systemName: "rectangle.stack") }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(DeckSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(DeckFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.title)
                            .font(.subheadline)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(filter == f ? Color.accentColor : Color.gray.opacity(0.2),
                                        in: Capsule())
                            .foregroundStyle(filter == f ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func card(_ bg: BackgroundImage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                CachedThumbnail(fileName: bg.localFileName)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                statusBadge(bg.status)
                    .padding(6)
                if !bg.isCached {
                    Image(systemName: "icloud.slash")
                        .padding(6)
                        .foregroundStyle(.white)
                }
            }
            Text(bg.title.isEmpty ? bg.id : bg.title)
                .font(.caption).lineLimit(1)
            if !bg.tags.isEmpty {
                Text(bg.tags.prefix(2).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func statusBadge(_ status: BackgroundStatus) -> some View {
        let color: Color = {
            switch status {
            case .new: return .blue
            case .starred: return .yellow
            case .used: return .green
            case .skipped: return .gray
            case .rejected: return .red
            }
        }()
        return Text(status.displayName)
            .font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }

    private var filtered: [BackgroundImage] {
        var items = state.deckBackgrounds

        switch filter {
        case .all: break
        case .new: items = items.filter { $0.status == .new }
        case .starred: items = items.filter { $0.status == .starred }
        case .used: items = items.filter { $0.status == .used }
        case .skipped: items = items.filter { $0.status == .skipped }
        }

        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter {
                $0.title.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
                || ($0.notes?.lowercased().contains(q) ?? false)
            }
        }

        switch sort {
        case .priority: items.sort { $0.priority > $1.priority }
        case .title: items.sort { $0.title < $1.title }
        case .recentlyUsed: items.sort { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
        case .sheetOrder: break
        }
        return items
    }
}

#Preview {
    NavigationStack { DeckView().environmentObject(AppState()) }
}
