import Foundation
import UniformTypeIdentifiers

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

    /// 程序构造（§125）：打开链内部按轻量目标合成
    /// 等价条目用，解码路径不变
    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        size: Int64?,
        mtime: Double?,
        mimeType: String?
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.mtime = mtime
        self.mimeType = mimeType
    }

    enum CodingKeys: String, CodingKey {
        case name, path, size, mtime
        case isDirectory = "is_directory"
        case mimeType = "mime_type"
    }

    public var modifiedAt: Date? {
        mtime.map { Date(timeIntervalSince1970: $0) }
    }

    /// 影音分类（§473 件三，改走平台原生 UTType 单
    /// 源）：mime 在位先经 UTType(mimeType:) 判
    /// conformance；mime 缺失、或 mime 对应的类型不
    /// 属媒体（octet-stream 等）时，再以文件扩展名
    /// 经 UTType(filenameExtension:) 判——旧手工扩
    /// 展名全表与「mime 非媒体前缀即 return nil」的
    /// 短路一并退役
    public enum MediaKind: Sendable {
        case image, video, audio
    }

    public var mediaKind: MediaKind? {
        guard !isDirectory else { return nil }
        if let mimeType,
           let type = UTType(mimeType: mimeType),
           let kind = Self.kind(of: type) {
            return kind
        }
        let ext = (name as NSString).pathExtension
        if !ext.isEmpty,
           let type = UTType(filenameExtension: ext),
           let kind = Self.kind(of: type) {
            return kind
        }
        return Self.fallbackKind(forExtension: ext.lowercased())
    }

    /// UTType conformance → 媒体种类（.movie/.audio/
    /// .image 三族即分类口径）
    private static func kind(of type: UTType) -> MediaKind? {
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .image) { return .image }
        return nil
    }

    /// 极小兜底（§473 件三）：只收 UTType 数据库查
    /// 不到的遗留格式，逐条注明实测依据（iOS 26 模
    /// 拟器 UTType(filenameExtension:) 与 UTType
    /// (mimeType:) 双路实测，2026-11-24，矩阵见
    /// MediaKindUTTypeMatrixTests）；新格式先查
    /// UTType、不许往本表随手加
    private static func fallbackKind(
        forExtension ext: String
    ) -> MediaKind? {
        switch ext {
        // mkv：Matroska 视频，系统类型库无条目（实测 nil）
        case "mkv": return .video
        // m2ts：蓝光传输流；同族 ts 可判、m2ts 查不到
        case "m2ts": return .video
        // mka：Matroska 音频，同 mkv 无条目（实测 nil）
        case "mka": return .audio
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
