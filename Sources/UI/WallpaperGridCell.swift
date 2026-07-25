import SwiftUI

/// One thumbnail cell in the library grid.
struct WallpaperGridCell: View {
    @EnvironmentObject private var appState: AppState
    let item: WallpaperItem
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(item: item)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.1),
                                          lineWidth: isSelected ? 3 : 1)
                    )
                    .opacity(item.kind.isSupported ? 1 : 0.55)

                badge
                    .padding(6)

                if isCurrent {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.white, .green)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }

            Text(item.project.title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(item.kind.isSupported ? .primary : .secondary)
        }
    }

    private var badge: some View {
        Text(item.kind.displayBadge)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(item.kind.isSupported ? .primary : .secondary)
    }
}

/// Loads a wallpaper thumbnail asynchronously from `ThumbnailProvider`.
struct ThumbnailView: View {
    @EnvironmentObject private var appState: AppState
    let item: WallpaperItem
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: placeholderSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: item.id) {
            image = await ThumbnailProvider.shared.thumbnail(
                for: item, storeRoot: appState.library.storeRoot
            )
        }
    }

    private var placeholderSymbol: String {
        switch item.kind {
        case .video: return "film"
        case .web: return "globe"
        case .image: return "photo"
        case .sceneUnsupported: return "cube.transparent"
        case .other: return "questionmark.square.dashed"
        }
    }
}
