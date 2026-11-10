import Foundation

/// 文件条目类别（0.36.31，文件页 v2 附记硬规矩）：菜
/// 单与失败页按它出项——不是一套菜单打天下。分类先
/// 看影音种（mime/扩展名既有判定），再看可读文本类，
/// 余按扩展名归办公/网页/压缩/其他。
public enum FileItemCategory: String, CaseIterable, Sendable {
    case text
    case pdf
    case office
    case html
    case image
    case video
    case audio
    case archive
    case other
}

/// 条目动作（菜单项单一事实源：文案与符号在本表钉
/// 死，各宿主只管按策略表取子集、按序渲染）
public enum FileItemAction: String, CaseIterable, Sendable {
    case preview
    case copyText
    case exportPDF
    case share
    case download
    case delete

    public var label: String {
        switch self {
        case .preview: return "预览"
        case .copyText: return "复制文字"
        case .exportPDF: return "导出 PDF"
        case .share: return "分享"
        case .download: return "下载到本地"
        case .delete: return "删除"
        }
    }

    public var systemImage: String {
        switch self {
        case .preview: return "eye"
        case .copyText: return "doc.on.doc"
        case .exportPDF: return "doc.richtext"
        case .share: return "square.and.arrow.up"
        case .download: return "arrow.down.to.line"
        case .delete: return "trash"
        }
    }
}

/// 打开失败页动作（规格附记：失败页同样按类型给动
/// 作，可下载的给重试/下载，其余按类型收敛）
public enum FileFailureAction: String, CaseIterable, Sendable {
    case retry
    case download
    case dismiss

    public var label: String {
        switch self {
        case .retry: return "重试"
        case .download: return "下载到本地"
        case .dismiss: return "知道了"
        }
    }

    public var systemImage: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .download: return "arrow.down.to.line"
        case .dismiss: return "checkmark"
        }
    }
}

/// 按类型出项的策略表（条目菜单/阅读面工具栏/失败页
/// 三面共用）：
/// - 复制文字：只给能确定性读出文字的类——可读文本
///   （阅读页原文）与 PDF（宿主 PDFKit 提取）。DOCX
///   等 Office 件 iOS 无系统文字提取通道，不摆灰项
///   充数（如实缺项，见 DESIGN §100 记账）；
/// - 导出 PDF：只给走阅读页的文本类（由块模型排版
///   生成），PDF 本体已是 PDF、不给；
/// - 敏感文件（SensitiveFilePolicy）：一切动作收回，
///   菜单空表、失败页只给「知道了」——凭据不出服务器
///   管理面。
public enum FileActionPolicy {
    public static func category(
        of entry: WorkspaceFileEntry
    ) -> FileItemCategory {
        guard !entry.isDirectory else { return .other }
        if let mediaKind = entry.mediaKind {
            switch mediaKind {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            }
        }
        if DocumentTextKind.kind(forFileName: entry.name) != nil {
            return .text
        }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "html", "htm":
            return .html
        case "doc", "docx", "xls", "xlsx", "ppt", "pptx",
             "pages", "numbers", "key", "rtf", "odt", "epub":
            return .office
        case "zip", "7z", "tar", "gz", "bz2", "xz", "rar":
            return .archive
        default:
            return .other
        }
    }

    /// 点开是否进文档阅读页（文本类且非敏感）
    public static func opensInReader(
        _ entry: WorkspaceFileEntry
    ) -> Bool {
        category(of: entry) == .text
            && !SensitiveFilePolicy.isSensitive(fileName: entry.name)
    }

    /// 条目菜单（资料库面：行 ⋮/长按、网格卡长按三处
    /// 同源同序）：预览打头、类型专属项居中、分享/下
    /// 载/删除收尾
    public static func menuActions(
        for entry: WorkspaceFileEntry
    ) -> [FileItemAction] {
        guard !entry.isDirectory,
              !SensitiveFilePolicy.isSensitive(fileName: entry.name)
        else { return [] }
        var actions: [FileItemAction] = [.preview]
        actions += typeSpecificActions(for: entry)
        actions += [.share, .download, .delete]
        return actions
    }

    /// 阅读/预览面工具栏：不给删除（离开列表面不删东
    /// 西，与 Muse 阅读面同克制），其余与菜单同源
    public static func readingActions(
        for entry: WorkspaceFileEntry
    ) -> [FileItemAction] {
        guard !entry.isDirectory,
              !SensitiveFilePolicy.isSensitive(fileName: entry.name)
        else { return [] }
        return typeSpecificActions(for: entry) + [.share, .download]
    }

    private static func typeSpecificActions(
        for entry: WorkspaceFileEntry
    ) -> [FileItemAction] {
        switch category(of: entry) {
        case .text:
            return [.copyText, .exportPDF]
        case .pdf:
            return [.copyText]
        case .office, .html, .image, .video, .audio,
             .archive, .other:
            return []
        }
    }

    /// 打开失败页动作集：可渲染类失败多为取数问题——
    /// 给重试＋下载；压缩/未知类失败多为格式不支持——
    /// 重试无益，只给下载＋知道了；敏感文件只给知道了
    /// （连下载都不许，凭据不外带）
    public static func failureActions(
        for entry: WorkspaceFileEntry
    ) -> [FileFailureAction] {
        if SensitiveFilePolicy.isSensitive(fileName: entry.name) {
            return [.dismiss]
        }
        switch category(of: entry) {
        case .text, .pdf, .office, .html, .image, .video, .audio:
            return [.retry, .download]
        case .archive, .other:
            return [.download, .dismiss]
        }
    }
}
