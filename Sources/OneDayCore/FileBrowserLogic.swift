import Foundation

/// 面包屑一段：显示名＋点击跳达的绝对路径
public struct FileCrumb: Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// 文件浏览纯逻辑（P8 文件屏升级，0.14.0）：排序/过滤/
/// 面包屑/路径拼装/上传请求要素（data URL、MIME 推断、
/// 大小上限）/图标盒 pastel 轮换。全部无副作用、确定性，
/// App 层与单测共用。
public enum FileBrowserLogic {
    /// 上传走 POST /api/files/upload 的 JSON data_url 形态
    /// （base64 膨胀约 1.37 倍），客户端先把原始字节卡在
    /// 25MB，超出如实提示不发请求。
    public static let uploadByteLimit = 25 * 1024 * 1024

    /// App 上传在 managed 根下的专属落点目录名
    /// （聚合列表里标「App 上传」来源）
    public static let uploadsDirectoryName = "uploads"

    public enum SortKey: String, CaseIterable, Sendable {
        case name
        case modified
        case size

        public var label: String {
            switch self {
            case .name: return "名称"
            case .modified: return "修改时间"
            case .size: return "大小"
            }
        }
    }

    /// 排序：目录恒在前；name 升序，modified/size 降序
    /// （文件面惯例，新/大在前）；同键以名称升序兜底，
    /// 保证结果稳定。目录的 size 为 nil 不参与比较。
    /// ascending（0.36.31，系统文件页排序行方向钮）：
    /// nil＝沿上文默认向；true/false 显式定方向——name
    /// 降序直接反转比较，modified/size 升序改小/旧在
    /// 前；兜底名称比较恒升序（只翻主比较向，稳定口径
    /// 不变）。
    public static func sorted(
        _ entries: [WorkspaceFileEntry], by key: SortKey,
        ascending: Bool? = nil
    ) -> [WorkspaceFileEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            switch key {
            case .name:
                if ascending == false {
                    return a.name.localizedStandardCompare(b.name)
                        == .orderedDescending
                }
            case .modified:
                let am = a.mtime ?? 0
                let bm = b.mtime ?? 0
                if am != bm {
                    return ascending == true ? am < bm : am > bm
                }
            case .size:
                let aSize = a.size ?? -1
                let bSize = b.size ?? -1
                if aSize != bSize {
                    return ascending == true
                        ? aSize < bSize : aSize > bSize
                }
            }
            return a.name.localizedStandardCompare(b.name)
                == .orderedAscending
        }
    }

    /// 段内搜索：按名称不分大小写包含过滤；空查询原样返回
    public static func filtered(
        _ entries: [WorkspaceFileEntry], query: String
    ) -> [WorkspaceFileEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
        }
    }

    /// 面包屑：path 在 root 之下时逐级展开（含根段）；
    /// path 就是 root 时只回根段；path 不在 root 下
    /// （异常输入）只回一段当前目录名，不编造层级。
    public static func breadcrumbs(
        root: String, path: String
    ) -> [FileCrumb] {
        let cleanRoot = trimmedTrailingSlash(root)
        let rootName = (cleanRoot as NSString).lastPathComponent
        guard path == cleanRoot || path.hasPrefix(cleanRoot + "/") else {
            return [FileCrumb(
                name: (path as NSString).lastPathComponent, path: path
            )]
        }
        var crumbs = [FileCrumb(name: rootName, path: cleanRoot)]
        guard path != cleanRoot else { return crumbs }
        var current = cleanRoot
        let rest = path.dropFirst(cleanRoot.count + 1)
        for part in rest.split(separator: "/") {
            current += "/" + part
            crumbs.append(FileCrumb(name: String(part), path: current))
        }
        return crumbs
    }

    /// 相对路径面包屑（Box 工作区等相对根场景）：
    /// rootName 为根段显示名，path 为相对路径（"" 表示根）
    public static func relativeBreadcrumbs(
        rootName: String, path: String
    ) -> [FileCrumb] {
        var crumbs = [FileCrumb(name: rootName, path: "")]
        guard !path.isEmpty else { return crumbs }
        var current = ""
        for part in path.split(separator: "/") {
            current = current.isEmpty ? String(part) : current + "/" + part
            crumbs.append(FileCrumb(name: String(part), path: current))
        }
        return crumbs
    }

    public static func joinPath(directory: String, name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// 新建文件夹名校验：去空白后非空、不含路径分隔、
    /// 不是 "." / ".."、不含换行。服务端在 locked_root 内
    /// 再做一层约束，这里先把明显非法的挡在客户端。
    public static func isValidFolderName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return !name.contains("/") && !name.contains("\n")
    }

    /// 按扩展名推断 MIME（upload 的 data_url 用）；未知一律
    /// application/octet-stream，不猜更细的类型
    public static func mimeType(forFileName name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "svg": return "image/svg+xml"
        case "pdf": return "application/pdf"
        case "txt", "log": return "text/plain"
        case "md": return "text/markdown"
        case "json": return "application/json"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "zip": return "application/zip"
        case "mp3": return "audio/mpeg"
        case "m4a": return "audio/mp4"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "doc": return "application/msword"
        case "docx":
            return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "ppt": return "application/vnd.ms-powerpoint"
        case "pptx":
            return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        default: return "application/octet-stream"
        }
    }

    public static func makeDataURL(data: Data, fileName: String) -> String {
        "data:\(mimeType(forFileName: fileName));base64,"
            + data.base64EncodedString()
    }

    public static func isUploadSizeAllowed(byteCount: Int) -> Bool {
        byteCount > 0 && byteCount <= uploadByteLimit
    }

    /// 图标盒 pastel 轮换序号（0 sky / 1 green / 2 lavender /
    /// 3 orange，设计标准 §7 P8 锚：类型图标盒 pastel 轮换）：
    /// 按类别稳定取色，同类文件同色；未分类文件按名称的
    /// 稳定哈希（字节和）落 0...3，跨启动不变。
    public static func tintIndex(for entry: WorkspaceFileEntry) -> Int {
        if entry.isDirectory { return 3 }
        switch entry.mediaKind {
        case .image: return 0
        case .audio: return 1
        case .video: return 2
        case nil:
            if entry.isTextLike { return 1 }
            let sum = entry.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return sum % 4
        }
    }

    private static func trimmedTrailingSlash(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
