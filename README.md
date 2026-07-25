# Wallpaper Studio

一款 macOS 原生的动态壁纸应用（Swift / SwiftUI + AppKit），可导入并应用从
Windows 版 **Wallpaper Engine** 拷贝过来的创意工坊壁纸。

## 功能

- **视频壁纸**（mp4/mov，H.264/HEVC）——用 `AVQueuePlayer` + `AVPlayerLooper` 无缝循环
- **网页壁纸**（HTML/JS）——用 `WKWebView` 渲染，内置 Wallpaper Engine 的
  `window.wallpaperPropertyListener` / `wallpaperRegisterAudioListener` API 垫片，
  支持自定义属性（颜色 / 滑块 / 开关 / 下拉 / 文本）实时联动
- **静态图片壁纸**（jpg/png/gif/webp…）——`NSImageView` 铺满显示，GIF 自动播放；
  也可直接在导入面板里选单张图片文件
- **场景壁纸（`scene.pkg`）静态提取**——内置纯 Swift 的 PKG 解包器 + TEX 解码器
  （支持 RGBA8888 / DXT1/3/5 / LZ4 / 内嵌 png/jpg/gif），从场景中抽出主图静态显示
  （**舍弃**粒子与光效动态）。导入时自动尝试；旧的场景项可在详情页手动「提取为静态壁纸」
- **导入**：选择单个壁纸文件夹，或整个 `steamapps/workshop/content/431960/` 目录，
  自动递归识别含 `project.json` 的壁纸并复制进本地库
- **多显示器**：每块屏幕可分配不同壁纸，拔插/重排后自动恢复
- **省电策略**：全屏应用、低电量、显示器休眠时自动暂停
- **菜单栏常驻**：快速切换、暂停/继续、打开壁纸库
- **开机自启动**（`SMAppService`）

## 下载与安装（无需 Xcode）

到 [Releases 页面](../../releases/latest)下载最新的 `Wallpaper-Studio-x.y.z.zip`，
解压后把 `Wallpaper Studio.app` 拖进 `/Applications`。

由于是本地 ad-hoc 签名（未经 Apple 公证），**首次打开需右键 →「打开」**，
或在终端运行：

```bash
xattr -dr com.apple.quarantine "/Applications/Wallpaper Studio.app"
```

系统要求：macOS 14 (Sonoma) 或更高版本。

## 从 Windows 拷贝壁纸

Wallpaper Engine 的创意工坊壁纸位于：

```
…/Steam/steamapps/workshop/content/431960/<壁纸ID>/
```

每个壁纸文件夹里含一个 `project.json` 和资源文件（`video.mp4` / `index.html` /
`scene.pkg`）。把整个 `431960` 目录（或单个壁纸文件夹）拷到 Mac，然后在应用里
「导入壁纸」选中它即可。

> **`.webm` 视频**：AVPlayer 不支持 webm/VP9，这类壁纸导入后会标记为不支持。
> 若本机装了 ffmpeg（`brew install ffmpeg`），可在壁纸详情里一键转码为 mp4。

## 构建与运行

需要 Xcode 15+（macOS 14 SDK）与 [XcodeGen](https://github.com/yonyz/XcodeGen)。

```bash
brew install xcodegen          # 首次
xcodegen generate              # 生成 WallpaperStudio.xcodeproj
open WallpaperStudio.xcodeproj # 用 Xcode 打开，⌘R 运行
```

或用命令行构建：

```bash
xcodebuild -scheme WallpaperStudio -configuration Debug build
```

新增/删除源文件后重新执行 `xcodegen generate` 刷新工程（源码按目录自动纳入）。

## 使用提示

- **Gatekeeper**：把 `.app` 拷到别的 Mac 首次打开时，右键 →「打开」以绕过未签名提示。
- **开机自启动**需要应用位于固定位置（建议放入 `/Applications`）。
- macOS 自带的动态壁纸会显示在本应用壁纸「下面」，视觉无冲突但会额外耗电，
  建议在「系统设置 → 墙纸」里设为静态壁纸。
- macOS 的「点按壁纸以显示桌面」手势与本应用共存正常（壁纸窗口位于桌面图标之下）。

## 架构

| 模块 | 职责 |
|---|---|
| `Sources/Library` | `project.json` 容错解析、导入、缩略图、webm 转码、图片壁纸合成 |
| `Sources/ScenePkg` | scene.pkg 解包（PKG/TEX/DXT/LZ4）与主图静态提取 |
| `Sources/Desktop` | 桌面层窗口、按显示器分配、屏幕变化跟踪 |
| `Sources/Renderers` | 视频 / 网页 / 图片渲染器 + 工厂（未来完整 scene 渲染器接入点） |
| `Sources/Policy` | 电源 / 全屏 / 休眠检测 → 统一的暂停决策 |
| `Sources/SettingsStore` | 库持久化、偏好设置、登录项 |
| `Sources/UI`、`Sources/MenuBar` | SwiftUI 壁纸库与菜单栏 |
| `Tools/make-icon.swift` | 从 `image.png` 生成 `AppIcon.icns` 的一次性脚本 |

## 已知限制

- `scene.pkg` 仅提取**静态主图**；粒子、着色器、光效等动态效果不渲染
  （完整场景渲染器工程量极大，暂不实现）。含视频纹理（mp4）的场景无法提取
- 网页壁纸的音频可视化为静音桩（不采集系统音频）
- 未上架 Mac App Store，无沙盒（面向个人使用/直接分发）
