import SwiftUI

/// Loads a downsampled cached image off the main thread and displays it.
struct CachedThumbnail: View {
    let fileName: String?
    var maxPixel: CGFloat = 400

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.gray.opacity(0.2))
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: fileName) {
            await load()
        }
    }

    private func load() async {
        guard let fileName else { image = nil; return }
        let max = maxPixel
        let loaded = await Task.detached(priority: .userInitiated) {
            ImageCacheService.loadThumbnail(fileName: fileName, maxPixel: max)
        }.value
        await MainActor.run { self.image = loaded }
    }
}
