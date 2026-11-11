import Foundation

/// 文件类型图标解析（§128，C8 定版）：扩展名→图标资产
/// slug 的单一事实源，供 FileIconBox／FileTypeFace 查
/// 表渲染。资产是 15 枚自制 3D 黏土风图标（256×256
/// 白底 PNG，Assets 内 fileicon-<slug>，路线 A 白色圆
/// 角砖承载、深色模式保持亮砖），构成对表 Muse 内部
/// legacy 文件家族（通用文档＋格式变体＋文件夹开合＋
/// 影音＋归档），映射口径以 file-icons-assets/README
/// 为准、对表 §125 的 FileItemCategory／FileOpenRoute。
///
/// 历史口径就此退役：0.22.0 的「身份色块＋白色粗体单
/// 字／SF 符号」字形表（W/P/X 字母块）——C8 调研定案
/// （file-icons-benchmark-20261111.md）：Adobe／微软
/// 官方品牌图第三方明文禁用、同行真实感全靠自绘成
/// 套，本表不再有字形与底色概念。分组沿旧表逐项对
/// 齐，增补四处：①code 组新增（源码类扩展名旧表无
/// 组、原落 default；html/htm 自 safari 符号改归本
/// 组，尖括号即其语义）②app 组新增（可安装件）③
/// archive 补 rar ④文档类通用回落 document（text/
/// office 类未命中专属组者），其余一切落 unknown。
public struct DeliverableIconStyle: Equatable, Sendable {
    /// 资产 slug（15 枚家族成员名）
    public let slug: String

    public init(slug: String) {
        self.slug = slug
    }

    /// Assets.xcassets 内的 imageset 名
    public var assetName: String { "fileicon-\(slug)" }

    /// 回落 slug／资源名：任一枚资源缺失时呈现端落它，
    /// 不许空白、不许回退字形（§128 验收口径）
    public static let fallbackSlug = "unknown"
    public static let fallbackAssetName = "fileicon-unknown"

    /// 全部 slug（资产完整性对账用，顺序同资产目录）
    public static let allSlugs: [String] = [
        "document", "word", "text", "pdf", "sheet",
        "slides", "code", "archive", "folder", "folder-open",
        "image", "video", "audio", "app", "unknown",
    ]

    public static func style(
        forFileName name: String,
        isDirectory: Bool = false,
        isExpanded: Bool = false
    ) -> DeliverableIconStyle {
        if isDirectory {
            return DeliverableIconStyle(
                slug: isExpanded ? "folder-open" : "folder"
            )
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "doc", "docx":
            return DeliverableIconStyle(slug: "word")
        case "ppt", "pptx":
            return DeliverableIconStyle(slug: "slides")
        case "xls", "xlsx", "csv":
            return DeliverableIconStyle(slug: "sheet")
        case "pdf":
            return DeliverableIconStyle(slug: "pdf")
        case "md", "txt", "rtf":
            return DeliverableIconStyle(slug: "text")
        case "html", "htm",
             "swift", "py", "js", "ts", "jsx", "tsx",
             "json", "yaml", "yml", "toml", "xml",
             "css", "scss", "c", "h", "m", "mm",
             "cpp", "cxx", "hpp", "java", "kt", "kts",
             "go", "rs", "rb", "php", "sh", "bash",
             "zsh", "sql", "pl", "lua", "vue":
            return DeliverableIconStyle(slug: "code")
        case "zip", "7z", "tar", "gz", "rar":
            return DeliverableIconStyle(slug: "archive")
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return DeliverableIconStyle(slug: "image")
        case "mp4", "mov", "m4v":
            return DeliverableIconStyle(slug: "video")
        case "mp3", "wav", "m4a", "aac":
            return DeliverableIconStyle(slug: "audio")
        case "ipa", "apk", "app", "dmg", "pkg", "exe", "msi":
            return DeliverableIconStyle(slug: "app")
        case "odt", "ods", "odp",
             "docm", "xlsm", "xlsb", "pptm",
             "pages", "numbers", "key", "epub", "log":
            // 文档类通用回落：text/office 类里没有专属
            // 身份的成员（开放文档格式、宏启 Office 变
            // 体、iWork 三件、电子书、日志）
            return DeliverableIconStyle(slug: "document")
        default:
            return DeliverableIconStyle(slug: "unknown")
        }
    }
}
