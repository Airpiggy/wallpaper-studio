import SwiftUI

/// A horizontal strip showing each connected display at true aspect ratio, its
/// name, and the wallpaper thumbnail currently applied to it. In independent
/// mode a display can be selected as the apply target; a mode switch toggles
/// sync vs. independent.
struct DisplayStripView: View {
    @EnvironmentObject private var appState: AppState

    private var infos: [AppState.DisplayInfo] {
        // Touch displaysVersion so the strip refreshes on config/assignment change.
        _ = appState.displaysVersion
        return appState.displayInfos
    }

    private var isSync: Bool { appState.settings.sameOnAllDisplays }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(infos) { info in
                        DisplayCard(
                            info: info,
                            isSync: isSync,
                            isSelected: !isSync && appState.selectedDisplayUUID == info.id
                        )
                        .onTapGesture {
                            guard !isSync else { return }
                            appState.selectedDisplayUUID = info.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            if infos.count > 1 {
                VStack(alignment: .trailing, spacing: 4) {
                    Picker("", selection: Binding(
                        get: { isSync },
                        set: { appState.setSameOnAllDisplays($0) }
                    )) {
                        Text("所有屏同步").tag(true)
                        Text("每屏独立").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)

                    Text(isSync ? "所有显示器共用一张壁纸" : "点选显示器后再应用壁纸")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// One display's preview card: aspect-correct thumbnail + name.
private struct DisplayCard: View {
    @EnvironmentObject private var appState: AppState
    let info: AppState.DisplayInfo
    let isSync: Bool
    let isSelected: Bool

    private let height: CGFloat = 66
    private var width: CGFloat { max(48, min(height * info.aspect, 200)) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.85))

                if let item = info.assignedItem {
                    ThumbnailView(item: item)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "display")
                            .foregroundStyle(.secondary)
                        Text("未设置").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 3 : 1)
            )

            HStack(spacing: 3) {
                if info.isMain {
                    Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(.yellow)
                }
                Text(info.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(width: width + 24)
        }
        .opacity(isSync ? 0.92 : 1)
        .help(info.assignedItem?.project.title ?? "未设置壁纸")
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        return .black.opacity(0.15)
    }
}
