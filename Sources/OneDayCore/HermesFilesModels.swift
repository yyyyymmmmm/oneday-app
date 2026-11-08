import Foundation

// MARK: - 工作区文件（GET /api/files，2026-11-08 生产实查）
//
// 回执形态（实查 /opt/data 根与子目录）：
// {"path": "/opt/data", "parent": null, "root": "/opt/data",
//  "locked_root": "/opt/data", "can_change_path": false,
//  "entries": [{"name": ".local", "path": "/opt/data/.local",
//               "is_directory": true, "size": null,
//               "mtime": 1794141188.88, "mime_type": null}]}
// 根被 locked_root 锁死在服务端数据目录内，path 只能在其下浏览。
// 删除：DELETE /api/files，body {path, recursive}（openapi
// ManagedFileDelete）。下载/预览：GET /api/files/download?path=
// 返回原始字节；文本直读另有 GET /api/files/read。

public struct WorkspaceFileEntry: Decodable, Sendable, Identifiable, Hashable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?
    /// 修改时间（epoch 秒，可为浮点）
    public let mtime: Double?
    public let mimeType: String?

    public var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, path, size, mtime
        case isDirectory = "is_directory"
        case mimeType = "mime_type"
    }

    public var modifiedAt: Date? {
        mtime.map { Date(timeIntervalSince1970: $0) }
    }

    /// 影音分类：先看 mime_type，缺失时按扩展名兜底
    public enum MediaKind: Sendable {
        case image, video, audio
    }

    public var mediaKind: MediaKind? {
        guard !isDirectory else { return nil }
        if let mimeType {
            if mimeType.hasPrefix("image/") { return .image }
            if mimeType.hasPrefix("video/") { return .video }
            if mimeType.hasPrefix("audio/") { return .audio }
            return nil
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp":
            return .image
        case "mp4", "mov", "m4v", "webm", "mkv":
            return .video
        case "mp3", "m4a", "wav", "ogg", "flac", "aac":
            return .audio
        default:
            return nil
        }
    }

    /// 文本类（可直接预览正文）：mime 或扩展名判定
    public var isTextLike: Bool {
        if let mimeType {
            if mimeType.hasPrefix("text/") { return true }
            if ["application/json", "application/xml", "application/x-yaml"]
                .contains(mimeType) { return true }
        }
        let ext = (name as NSString).pathExtension.lowercased()
        return ["txt", "md", "json", "log", "yaml", "yml", "xml", "csv",
                "swift", "py", "sh", "html", "css", "js", "ts"].contains(ext)
    }
}

public struct FilesListing: Decodable, Sendable {
    public let path: String
    public let parent: String?
    public let entries: [WorkspaceFileEntry]
    public let root: String?
    public let lockedRoot: String?
    public let canChangePath: Bool?

    enum CodingKeys: String, CodingKey {
        case path, parent, entries, root
        case lockedRoot = "locked_root"
        case canChangePath = "can_change_path"
    }
}

// MARK: - 系统状态（GET /api/system/stats，2026-11-08 生产实查）
//
// {"os": "Linux", "os_release": "3.10.0-…", "platform": "…",
//  "arch": "x86_64", "hostname": "…", "python_version": "3.14.9",
//  "hermes_version": "0.23.0", "cpu_count": 4, "cpu_percent": 2.5,
//  "load_avg": [0.07, 0.09, 0.12], "uptime_seconds": 2358766,
//  "memory": {"total": …, "available": …, "used": …, "percent": 46.7},
//  "disk": {"total": …, "used": …, "free": …, "percent": 45.3},
//  "process": {"pid": 155, "rss": …, "create_time": …, "num_threads": 11}}

public struct SystemStats: Decodable, Sendable {
    public struct Memory: Decodable, Sendable {
        public let total: Int64?
        public let available: Int64?
        public let used: Int64?
        public let percent: Double?
    }

    public struct Disk: Decodable, Sendable {
        public let total: Int64?
        public let used: Int64?
        public let free: Int64?
        public let percent: Double?
    }

    public struct Process: Decodable, Sendable {
        public let pid: Int?
        public let rss: Int64?
        public let numThreads: Int?

        enum CodingKeys: String, CodingKey {
            case pid, rss
            case numThreads = "num_threads"
        }
    }

    public let hermesVersion: String?
    public let hostname: String?
    public let os: String?
    public let osRelease: String?
    public let platform: String?
    public let arch: String?
    public let pythonVersion: String?
    public let cpuCount: Int?
    public let cpuPercent: Double?
    public let loadAvg: [Double]?
    public let uptimeSeconds: Double?
    public let memory: Memory?
    public let disk: Disk?
    public let process: Process?

    enum CodingKeys: String, CodingKey {
        case hostname, os, platform, arch, memory, disk, process
        case hermesVersion = "hermes_version"
        case osRelease = "os_release"
        case pythonVersion = "python_version"
        case cpuCount = "cpu_count"
        case cpuPercent = "cpu_percent"
        case loadAvg = "load_avg"
        case uptimeSeconds = "uptime_seconds"
    }
}
