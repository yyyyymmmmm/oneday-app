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
    /// 置顶/取消置顶（§131 对齐包，D8）：客户端整理
    /// 动作——只改本机置顶集（FilePinSet），不触服务
    /// 器状态（与 Muse Pin 同语义）。两态同表出签，
    /// 由宿主按当前置顶态取一
    case pin
    case unpin
    /// 重命名（§131，D8）：服务端无改名端点，宿主走
    /// 既有原语组合链（下载→上传新名→回读校验→删
    /// 旧），判定与新名规整在 FileRenamePlan 单源
    case rename
    /// 在文件页中打开（§131，D8）：回指文件页并定
    /// 位高亮该行（AppState.routes.fileRevealPath 通道）
    case openInFiles

    public var label: String {
        switch self {
        case .preview: return "预览"
        case .copyText: return "复制文字"
        case .exportPDF: return "导出 PDF"
        case .share: return "分享"
        case .download: return "下载到本地"
        case .delete: return "删除"
        case .pin: return "置顶"
        case .unpin: return "取消置顶"
        case .rename: return "重命名"
        case .openInFiles: return "在资源库中打开"
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
        case .pin: return "pin"
        case .unpin: return "pin.slash"
        case .rename: return "pencil"
        case .openInFiles: return "folder"
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

/// 中间页主钮（§125 落点列）：按类型一颗主钮——文
/// 本类「阅读」、可预览类「预览」、音视频「播放」、
/// 表格「查看表格」、压缩包「保存到文件」；其余不
/// 可预览类与敏感文件无主钮（nil），中间页只给说明
/// 行与次动作。文案在本表单源钉死
public enum FileLandingAction: String, CaseIterable, Sendable {
    case read
    case preview
    case play
    case viewTable
    case saveToFiles

    public var label: String {
        switch self {
        case .read: return "阅读"
        case .preview: return "预览"
        case .play: return "播放"
        case .viewTable: return "查看表格"
        case .saveToFiles: return "保存到文件"
        }
    }

    public var systemImage: String {
        switch self {
        case .read: return "doc.text"
        case .preview: return "eye"
        case .play: return "play.fill"
        case .viewTable: return "tablecells"
        case .saveToFiles: return "square.and.arrow.down"
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
        return category(
            forFileName: entry.name, mediaKind: entry.mediaKind
        )
    }

    /// 分类名称口径（§125）：中间页/路由表只有文件
    /// 名与媒体种类、没有完整条目时走本口径，与条目
    /// 口径同序同果（先媒体种类、再可读文本类、余按
    /// 扩展名）。mediaKind 传 nil＝无 mime 线索：经
    /// 合成条目按扩展名推导（影音扩展名表在条目
    /// mediaKind 里，单源复用、不另抄一份）
    public static func category(
        forFileName name: String,
        mediaKind: WorkspaceFileEntry.MediaKind?
    ) -> FileItemCategory {
        let mediaKind = mediaKind ?? WorkspaceFileEntry(
            name: name, path: name, isDirectory: false,
            size: nil, mtime: nil, mimeType: nil
        ).mediaKind
        if let mediaKind {
            switch mediaKind {
            case .image: return .image
            case .video: return .video
            case .audio: return .audio
            }
        }
        if DocumentTextKind.kind(forFileName: name) != nil {
            return .text
        }
        switch (name as NSString).pathExtension.lowercased() {
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

    /// 表格文件（xls/xlsx）：office 档内的转码呈现
    /// 特判（§125 路由表与中间页落点列共用本判据，
    /// 不许各写一份扩展名判断）
    public static func isSpreadsheet(_ name: String) -> Bool {
        switch (name as NSString).pathExtension.lowercased() {
        case "xls", "xlsx": return true
        default: return false
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

    /// 打开页（中间页）顶栏菜单动作集（§131 对齐包，
    /// D8 补齐）：置顶态打头（按当前态出 pin/unpin
    /// 一项）、类型专属居中、分享/下载、重命名与「在
    /// 文件页中打开」收尾。仍守阅读面克制——不给删
    /// 除（删除归列表面，D8 口径删除不进本包）；敏
    /// 感文件与目录全收回（空表），与全表同纪律
    public static func openPageActions(
        for entry: WorkspaceFileEntry, isPinned: Bool
    ) -> [FileItemAction] {
        guard !entry.isDirectory,
              !SensitiveFilePolicy.isSensitive(fileName: entry.name)
        else { return [] }
        return [isPinned ? .unpin : .pin]
            + typeSpecificActions(for: entry)
            + [.share, .download, .rename, .openInFiles]
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

    /// 中间页主钮（§125 落点列，新增第四列；既有三
    /// 列语义不动）：按分类出主钮，敏感文件收回
    public static func landingPrimary(
        for entry: WorkspaceFileEntry
    ) -> FileLandingAction? {
        guard !entry.isDirectory else { return nil }
        return landingPrimary(
            forFileName: entry.name, mediaKind: entry.mediaKind
        )
    }

    /// 中间页主钮名称口径：与路由表同判（表格特判
    /// 先于 office 一般预览）
    public static func landingPrimary(
        forFileName name: String,
        mediaKind: WorkspaceFileEntry.MediaKind?
    ) -> FileLandingAction? {
        guard !SensitiveFilePolicy.isSensitive(fileName: name)
        else { return nil }
        if isSpreadsheet(name) { return .viewTable }
        switch category(forFileName: name, mediaKind: mediaKind) {
        case .text:
            return .read
        case .pdf, .office, .html, .image:
            return .preview
        case .video, .audio:
            return .play
        case .archive:
            return .saveToFiles
        case .other:
            return nil
        }
    }
}
