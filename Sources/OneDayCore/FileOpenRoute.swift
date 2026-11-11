import Foundation

/// 文件行号锚点（§125 搭车，ekko 式 `#L12-L20`）：
/// 助手文本里的文件路径可带行段后缀，点开后经中
/// 间页进阅读页定位高亮。仅 text 类消费（路由表
/// 裁决），其余类型解析保留、呈现忽略，不假装能
/// 在 QuickLook 里定位行号。
public struct FileLineAnchor: Equatable, Sendable {
    public let startLine: Int
    public let endLine: Int

    public init?(startLine: Int, endLine: Int) {
        guard startLine >= 1, endLine >= startLine else {
            return nil
        }
        self.startLine = startLine
        self.endLine = endLine
    }

    /// 解析锚点片段：接受 `L12`、`L12-L20`、
    /// `L12-20` 与带 `#` 前缀的完整形态；非法或
    /// 行号越界（<1、止<起）回 nil，不猜
    public static func parse(_ fragment: String) -> FileLineAnchor? {
        var text = fragment.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.hasPrefix("L") else { return nil }
        let parts = text.dropFirst().split(
            separator: "-", omittingEmptySubsequences: false
        )
        func number(_ part: Substring) -> Int? {
            var token = part
            if token.hasPrefix("L") { token = token.dropFirst() }
            guard !token.isEmpty,
                  token.allSatisfy({ $0.isNumber })
            else { return nil }
            return Int(token)
        }
        switch parts.count {
        case 1:
            guard let line = number(parts[0]) else { return nil }
            return FileLineAnchor(startLine: line, endLine: line)
        case 2:
            guard let start = number(parts[0]),
                  let end = number(parts[1])
            else { return nil }
            return FileLineAnchor(startLine: start, endLine: end)
        default:
            return nil
        }
    }

    /// 把「路径＋可选锚点」拆开：`/a/b.py#L12-L20`
    /// → ("/a/b.py", 锚点)；无锚点或锚点非法时原
    /// 样回 (原文, nil)
    public static func split(
        pathWithAnchor: String
    ) -> (path: String, anchor: FileLineAnchor?) {
        guard let hash = pathWithAnchor.lastIndex(of: "#") else {
            return (pathWithAnchor, nil)
        }
        let fragment = String(
            pathWithAnchor[pathWithAnchor.index(after: hash)...]
        )
        guard let anchor = parse(fragment) else {
            return (pathWithAnchor, nil)
        }
        return (String(pathWithAnchor[..<hash]), anchor)
    }
}

/// 带锚点的文件引用（FileRefDetector.detectAnchored
/// 的产出）：路径恒为干净路径，锚点单列
public struct FileAnchoredRef: Equatable, Sendable {
    public let path: String
    public let anchor: FileLineAnchor?

    public init(path: String, anchor: FileLineAnchor?) {
        self.path = path
        self.anchor = anchor
    }
}

/// 文件打开目标（§125 中间页的轻量值输入）：打开
/// 页只依赖名称／路径／可选大小／可选修改时间＋
/// 可选锚点——聊天侧由文件牌构造、文件页侧由条目
/// 构造，不要求先有完整 WorkspaceFileEntry。
public struct FileOpenTarget: Equatable, Sendable, Identifiable {
    public let name: String
    public let path: String

    /// 呈现标识（sheet(item:) 用）：同一路径即同一
    /// 打开目标，锚点差异不另开页
    public var id: String { path }
    public let size: Int64?
    public let modifiedAt: Date?
    public let mimeType: String?
    public let anchor: FileLineAnchor?

    public init(
        name: String,
        path: String,
        size: Int64? = nil,
        modifiedAt: Date? = nil,
        mimeType: String? = nil,
        anchor: FileLineAnchor? = nil
    ) {
        self.name = name
        self.path = path
        self.size = size
        self.modifiedAt = modifiedAt
        self.mimeType = mimeType
        self.anchor = anchor
    }

    public init(entry: WorkspaceFileEntry, anchor: FileLineAnchor? = nil) {
        self.init(
            name: entry.name,
            path: entry.path,
            size: entry.size,
            modifiedAt: entry.mtime.map {
                Date(timeIntervalSince1970: $0)
            },
            mimeType: entry.mimeType,
            anchor: anchor
        )
    }

    /// 仅有服务器路径时构造（聊天文件牌）：名称取
    /// 路径末段，大小/时间待元数据缓存回填
    public init(path: String, anchor: FileLineAnchor? = nil) {
        self.init(
            name: (path as NSString).lastPathComponent,
            path: path,
            anchor: anchor
        )
    }

    /// 媒体种类（mime 优先、扩展名兜底，与条目同
    /// 规——经合成条目取，不另立一套判定）
    public var mediaKind: WorkspaceFileEntry.MediaKind? {
        workspaceEntry.mediaKind
    }

    /// 文件分类（与条目路径同源：FileActionPolicy
    /// 名称口径）
    public var category: FileItemCategory {
        FileActionPolicy.category(
            forFileName: name, mediaKind: mediaKind
        )
    }

    /// 合成等价条目：供既有 entry 入参的策略表
    /// （FileActionPolicy 动作表）与阅读页复用——只
    /// 在打开链内部使用，不落库、不冒充服务器回读
    public var workspaceEntry: WorkspaceFileEntry {
        WorkspaceFileEntry(
            name: name,
            path: path,
            isDirectory: false,
            size: size,
            mtime: modifiedAt?.timeIntervalSince1970,
            mimeType: mimeType
        )
    }
}

/// 文件打开路由表（§125 规格 §5.3，纯函数）：输入
/// ＝打开目标＋canPreview 资格（§121 既有门，字节
/// 落盘后由 QL 判定；调用方未取字节时默认 true，
/// 取后为假一律降无预览行）。chat/文件页/中间页
/// 三处共用本表分流，不许各写一份扩展名判断。
public enum FileOpenRoute: Equatable, Sendable {
    /// 图片：直达既有全屏图片查看器，不经中间页
    case imageViewer
    /// 文本类：中间页 → 页内阅读页
    case reader
    /// PDF/Office/HTML/音视频：中间页 → 页内 QL 承载
    case quickLook
    /// xlsx/xls：中间页 → 伴生转码表格呈现
    case spreadsheet
    /// 压缩包：中间页无预览，主钮「保存到文件」
    case saveOnly
    /// 其余不可预览：中间页说明行＋分享/下载
    case infoOnly
    /// 敏感文件：中间页锁定分支（不渲染、不给下载）
    case locked

    public static func resolve(
        target: FileOpenTarget, canPreview: Bool = true
    ) -> FileOpenRoute {
        if SensitiveFilePolicy.isSensitive(fileName: target.name) {
            return .locked
        }
        switch target.category {
        case .image:
            return .imageViewer
        case .text:
            return .reader
        case .office where FileActionPolicy.isSpreadsheet(target.name):
            return .spreadsheet
        case .pdf, .office, .html, .video, .audio:
            return canPreview ? .quickLook : .infoOnly
        case .archive:
            return .saveOnly
        case .other:
            return .infoOnly
        }
    }
}
