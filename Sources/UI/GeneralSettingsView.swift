import SwiftUI

/// App preferences: playback policy, video audio, dock icon, launch at login.
struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var launchAtLogin = LoginItemManager.isEnabled

    private var settings: AppSettings { appState.settings }

    var body: some View {
        Form {
            Section("省电策略") {
                Toggle("全屏应用时暂停", isOn: Binding(
                    get: { settings.pauseOnFullscreen },
                    set: { settings.pauseOnFullscreen = $0; appState.policy.settingsChanged() }
                ))
                Toggle("使用电池且电量低时暂停", isOn: Binding(
                    get: { settings.pauseOnBattery },
                    set: { settings.pauseOnBattery = $0; appState.policy.settingsChanged() }
                ))
                if settings.pauseOnBattery {
                    Stepper("低电量阈值：\(settings.batteryThreshold)%",
                            value: Binding(
                                get: { settings.batteryThreshold },
                                set: { settings.batteryThreshold = $0; appState.policy.settingsChanged() }
                            ), in: 5...50, step: 5)
                }
            }

            Section("显示") {
                Toggle("多显示器使用同一壁纸", isOn: Binding(
                    get: { settings.sameOnAllDisplays },
                    set: { settings.sameOnAllDisplays = $0 }
                ))
                Toggle("视频壁纸静音", isOn: Binding(
                    get: { settings.muteVideo },
                    set: { settings.muteVideo = $0; appState.desktop.muteVideo = $0 }
                ))

                Picker("视频内存缓存上限", selection: Binding(
                    get: { settings.videoMemoryCacheLimitMB },
                    set: { appState.setVideoMemoryCacheLimit($0) }
                )) {
                    Text("关闭").tag(0)
                    Text("100 MB").tag(100)
                    Text("200 MB").tag(200)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                }
                Text("小于该大小的视频常驻内存循环播放，避免每次循环都从磁盘重新读取。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("系统") {
                Toggle("隐藏 Dock 图标（仅菜单栏）", isOn: Binding(
                    get: { settings.hideDockIcon },
                    set: { appState.setHideDockIcon($0) }
                ))
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        appState.setLaunchAtLogin(enabled)
                    }
                Text("提示：开机自启动需要将应用放在固定位置（如 /Applications）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }
}
