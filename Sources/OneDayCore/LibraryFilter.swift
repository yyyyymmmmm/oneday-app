import Foundation

/// 资源库筛选片（§452 定版③：不分栏——单列表＋顶
/// 部筛选片 全部/文档/图片/影音/其他＋搜索＋来源筛
/// 选）。分类派生单源：影音种类走 WorkspaceFile-
/// Entry.mediaKind、文档类走 FileItemCategory，不
/// 另立扩展名表。
public enum LibraryCategory: String, CaseIterable, Sendable {
    case all
    case documents
    case images
    case media
    case other

    public var label: String {
        switch self {
        case .all: return "全部"
        case .documents: return "文档"
        case .images: return "图片"
        case .media: return "影音"
        case .other: return "其他"
        }
    }

    /// 条目归片：目录归其他；图片/影音按 mediaKind；
    /// 文本/PDF/Office/HTML 归文档；压缩包与未分类
    /// 归其他
    public static func bucket(
        for entry: WorkspaceFileEntry
    ) -> LibraryCategory {
        if entry.isDirectory { return .other }
        switch entry.mediaKind {
        case .image: return .images
        case .video, .audio: return .media
        case nil: break
        }
        switch FileActionPolicy.category(
            forFileName: entry.name, mediaKind: entry.mediaKind
        ) {
        case .text, .pdf, .office, .html:
            return .documents
        case .image:
            return .images
        case .video, .audio:
            return .media
        case .archive, .other:
            return .other
        }
    }

    public func includes(_ entry: WorkspaceFileEntry) -> Bool {
        self == .all || Self.bucket(for: entry) == self
    }
}
