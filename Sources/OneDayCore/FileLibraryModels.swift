import Foundation

// MARK: - 文件库聚合读面（A-06，伴生 1.0.66）
//
// GET /api/oneday-bridge/file-library：文件页（DeliverablesView）
// 的聚合集由伴生一次下发——产出根、准入、去重、排序全在服务
// 端（oneday_seg_filelibrary.py 为单一事实源）。0.50.60 及之
// 前客户端自爬 /api/files 目录树（BFS＋600 静默截断＋客户端
// 准入）的形态就此退役，本文件只剩回执解码。
//
// 条目字段与 GET /api/files 的 entries 同形（name/path/
// is_directory/size/mtime/mime_type），多一个 source（产出根
// 语义名）；解码复用 WorkspaceFileEntry 本体，不另立第二形。

/// 文件库条目：工作区文件条目＋来源（产出目录语义名；
/// 来源只作数据层记录与排查，行副题不上屏）
public struct FileLibraryItem: Decodable, Sendable, Hashable {
    public let entry: WorkspaceFileEntry
    public let source: String

    public init(entry: WorkspaceFileEntry, source: String) {
        self.entry = entry
        self.source = source
    }

    public init(from decoder: Decoder) throws {
        entry = try WorkspaceFileEntry(from: decoder)
        let container = try decoder.container(
            keyedBy: SourceKey.self
        )
        source = try container.decode(String.self, forKey: .source)
    }

    private enum SourceKey: String, CodingKey {
        case source
    }
}

/// 文件库回执：items 为本页条目（默认整集），total 为准入
/// 总数（分页时仍报全量），truncated 恒 false——服务端无计
/// 数上限、永不静默截断（600 封顶随客户端爬树一并退役）
public struct FileLibraryPage: Decodable, Sendable {
    public let items: [FileLibraryItem]
    public let total: Int
    public let offset: Int
    public let limit: Int?
    public let truncated: Bool

    public init(
        items: [FileLibraryItem], total: Int, offset: Int,
        limit: Int?, truncated: Bool
    ) {
        self.items = items
        self.total = total
        self.offset = offset
        self.limit = limit
        self.truncated = truncated
    }
}
