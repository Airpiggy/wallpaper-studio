import Darwin
import Foundation

/// Reads this process's cumulative physical disk I/O counters — the same
/// numbers Activity Monitor shows as "Bytes Read"/"Bytes Written".
///
/// Page-cache hits do NOT increment these counters, which is exactly what makes
/// them the right instrument for verifying the memory-backed playback path:
/// once a wallpaper's bytes are served from mapped memory, `bytesRead` should
/// stop growing even though the video keeps looping.
enum DiskIOStats {
    /// Cumulative bytes physically read by this process, or nil if unavailable.
    static func currentBytesRead() -> UInt64? {
        current()?.ri_diskio_bytesread
    }

    /// Cumulative bytes physically written by this process, or nil if unavailable.
    static func currentBytesWritten() -> UInt64? {
        current()?.ri_diskio_byteswritten
    }

    private static func current() -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, rebound)
            }
        }
        return result == 0 ? info : nil
    }

    /// Human-readable byte count for logs (e.g. "1.23 GB").
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
