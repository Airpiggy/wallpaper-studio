import Foundation

/// Converts unsupported `.webm`/VP9 videos to H.264 `.mp4` using a locally
/// installed ffmpeg, if present. Purely optional — the app works without it.
enum ConversionService {
    /// Path to a usable ffmpeg binary, or nil if none is installed.
    static var ffmpegPath: String? {
        for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static var isAvailable: Bool { ffmpegPath != nil }

    enum ConversionError: LocalizedError {
        case ffmpegMissing
        case noSourceFile
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegMissing: return "未检测到 ffmpeg（可用 Homebrew 安装：brew install ffmpeg）"
            case .noSourceFile: return "找不到源视频文件"
            case .failed(let s): return "转码失败：\(s)"
            }
        }
    }

    /// Convert the item's webm asset to mp4 in-place in its folder. Returns the
    /// new file name (relative) on success.
    static func convertToMP4(sourceURL: URL) async throws -> URL {
        guard let ffmpeg = ffmpegPath else { throw ConversionError.ffmpegMissing }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ConversionError.noSourceFile
        }
        let outURL = sourceURL.deletingPathExtension().appendingPathExtension("mp4")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y", "-i", sourceURL.path,
                "-c:v", "libx264", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-movflags", "+faststart",
                outURL.path,
            ]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outURL)
                } else {
                    let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let msg = String(data: data.suffix(400), encoding: .utf8) ?? "unknown"
                    continuation.resume(throwing: ConversionError.failed(msg))
                }
            }
            do { try process.run() } catch {
                continuation.resume(throwing: ConversionError.failed(error.localizedDescription))
            }
        }
    }
}
