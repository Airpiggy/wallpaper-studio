import SwiftUI

/// The main window: a grid of imported wallpapers with import/apply controls.
struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: UUID?
    @State private var detailItem: WallpaperItem?
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    private var items: [WallpaperItem] {
        let all = appState.library.items.sorted { $0.addedDate > $1.addedDate }
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.project.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            DisplayStripView()
            Divider()
            content
            Divider()
            statusBar
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(item: $detailItem) { item in
            WallpaperDetailView(item: item)
                .environmentObject(appState)
                .frame(minWidth: 520, minHeight: 460)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                appState.importWallpapers()
            } label: {
                Label("导入壁纸", systemImage: "plus")
            }

            Button("示例壁纸") { appState.applySampleWallpaper() }

            Spacer()

            if let name = appState.currentWallpaperName {
                Label(appState.isPaused ? "\(name)（已暂停）" : name,
                      systemImage: "play.rectangle.fill")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            TextField("搜索", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { item in
                        WallpaperGridCell(
                            item: item,
                            isSelected: selection == item.id,
                            isCurrent: appState.isApplied(item.id)
                        )
                        .onTapGesture { selection = item.id }
                        .onTapGesture(count: 2) { appState.applyToCurrentTarget(item) }
                        .contextMenu {
                            Button("应用") { appState.applyToCurrentTarget(item) }
                            applyToMenu(for: item)
                            if !item.project.properties.isEmpty || item.kind.isSupported {
                                Button("详情与设置…") { detailItem = item }
                            }
                            Divider()
                            Button("删除", role: .destructive) {
                                appState.library.delete(item)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("还没有壁纸")
                .font(.title2.bold())
            Text("点击「导入壁纸」，选择从 Windows Wallpaper Engine 拷贝过来的\n创意工坊文件夹（含 project.json）。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("导入壁纸") { appState.importWallpapers() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// A submenu that applies `item` to a specific display (or all).
    @ViewBuilder
    private func applyToMenu(for item: WallpaperItem) -> some View {
        let infos = appState.displayInfos
        if infos.count > 1, item.kind.isSupported {
            Menu("应用到") {
                Button("所有显示器") { appState.apply(item, to: .all) }
                Divider()
                ForEach(infos) { info in
                    Button(info.name) { appState.apply(item, to: .display(info.id)) }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if let selected = items.first(where: { $0.id == selection }) {
                Button("应用") { appState.applyToCurrentTarget(selected) }
                    .disabled(!selected.kind.isSupported)
                Button("详情与设置…") { detailItem = selected }
                Button("删除", role: .destructive) { appState.library.delete(selected) }
            }
            Spacer()
            if let err = appState.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let reason = appState.policy.pauseReason, reason != .noWallpaper {
                Label(reason.message, systemImage: "pause.circle")
                    .foregroundStyle(.secondary).lineLimit(1)
            } else if let summary = appState.library.lastImportSummary {
                Text(summary).foregroundStyle(.secondary)
            }
            if appState.currentWallpaperName != nil {
                Button(appState.isPaused ? "继续" : "暂停") { appState.togglePause() }
                Button("清除") { appState.clearWallpaper() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
