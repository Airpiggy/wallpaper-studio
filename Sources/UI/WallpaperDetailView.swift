import SwiftUI

/// Wallpaper details + live property editor, shown as a sheet.
struct WallpaperDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let item: WallpaperItem

    @State private var values: [String: JSONValue] = [:]
    @State private var titleText: String = ""
    @State private var isConverting = false
    @State private var convertError: String?
    @State private var isExtracting = false
    @State private var extractError: String?

    /// A webm (or otherwise flagged) video that ffmpeg could rescue.
    private var canConvert: Bool {
        item.kind == .video && item.unsupportedReason != nil && ConversionService.isAvailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThumbnailView(item: item)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    if let desc = item.project.descriptionText, !desc.isEmpty {
                        Text(desc).foregroundStyle(.secondary)
                    }

                    if !item.project.tags.isEmpty {
                        Text("标签：" + item.project.tags.joined(separator: "、"))
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if let reason = item.unsupportedReason {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }

                    if canConvert {
                        HStack {
                            Button {
                                convert()
                            } label: {
                                Label("用 ffmpeg 转码为 mp4", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(isConverting)
                            if isConverting { ProgressView().controlSize(.small) }
                            if let convertError {
                                Text(convertError).font(.caption).foregroundStyle(.red)
                            }
                        }
                    } else if item.kind == .video && item.unsupportedReason != nil && !ConversionService.isAvailable {
                        Text("安装 ffmpeg（brew install ffmpeg）后可在此转码。")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if item.kind == .sceneUnsupported {
                        HStack {
                            Button {
                                extractScene()
                            } label: {
                                Label("提取为静态壁纸", systemImage: "photo.badge.arrow.down")
                            }
                            .disabled(isExtracting)
                            if isExtracting { ProgressView().controlSize(.small) }
                            if let extractError {
                                Text(extractError).font(.caption).foregroundStyle(.red)
                            }
                        }
                        Text("从 scene.pkg 中抽取主图静态显示（舍弃粒子/光效）。")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if !item.project.properties.isEmpty {
                        Text("自定义设置").font(.headline)
                        PropertyEditorView(
                            properties: item.project.properties,
                            values: $values
                        )
                        .onChange(of: values) { _, newValues in
                            appState.applyPropertyValues(newValues, for: item.id)
                        }
                    } else {
                        Text("该壁纸没有可自定义的属性。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                Text(item.kind.displayBadge).foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
                Button("应用") { appState.apply(item); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.kind.isSupported)
            }
            .padding(12)
        }
        .onAppear {
            values = item.effectiveProperties
            titleText = item.project.title
        }
    }

    private var header: some View {
        HStack {
            TextField("名称", text: $titleText)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .onSubmit { appState.library.rename(item, to: titleText) }
            Spacer()
        }
        .padding(12)
    }

    private func convert() {
        isConverting = true
        convertError = nil
        Task {
            let err = await appState.library.convertWebmToMP4(item)
            isConverting = false
            convertError = err
        }
    }

    private func extractScene() {
        isExtracting = true
        extractError = nil
        Task {
            let err = await appState.library.extractSceneImage(item)
            isExtracting = false
            extractError = err
            if err == nil { dismiss() }   // item upgraded to .image; reopen to see it
        }
    }
}
