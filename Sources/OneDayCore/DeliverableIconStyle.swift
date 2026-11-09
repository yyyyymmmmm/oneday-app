import Foundation

/// 交付物类型图标样式（0.22.0，视觉审计 F2 图标规格）：
/// 扩展名→字形＋身份底色的单一事实源，供 FileIconBox
/// 渲染。0.20.0 的旧画法是「SF 通用字形＋按类别哈希轮
/// 换的 pastel 底」——颜色不表类型、与 Muse 资源库的类
/// 型真图标（DOCX 蓝 W、PPTX 橙 P）并置即显廉价。本表
/// 按审计规格改身份色块：办公三件用白色粗体单字（W/P/
/// X，Office 品牌色）、PDF 红、图片/视频/音频各有专属
/// 色，未知回落中性灰 doc。底色是图标身份色、不作文字
/// 底，不受文字对比约束；pastel 轮换就此只留枢纽等装
/// 饰面（FileBrowserLogic.tintIndex 本体保留）。
/// 图片本体在影音段有 MediaCell 真缩略图面，本表只给
/// 文件行图标盒的回落字形（photo.fill）。
public struct DeliverableIconStyle: Equatable, Sendable {
    public enum Glyph: Equatable, Sendable {
        /// 白色粗体单字（办公三件）
        case letter(String)
        /// SF 符号名（白色填充字形）
        case symbol(String)
    }

    public let glyph: Glyph
    /// 底色（RRGGBB hex、无 # 前缀）
    public let backgroundHex: String

    public init(glyph: Glyph, backgroundHex: String) {
        self.glyph = glyph
        self.backgroundHex = backgroundHex
    }

    public static func style(
        forFileName name: String, isDirectory: Bool = false
    ) -> DeliverableIconStyle {
        if isDirectory {
            return DeliverableIconStyle(
                glyph: .symbol("folder.fill"), backgroundHex: "6E777D"
            )
        }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "doc", "docx":
            return DeliverableIconStyle(
                glyph: .letter("W"), backgroundHex: "2B579A"
            )
        case "ppt", "pptx":
            return DeliverableIconStyle(
                glyph: .letter("P"), backgroundHex: "C43E1C"
            )
        case "xls", "xlsx", "csv":
            return DeliverableIconStyle(
                glyph: .letter("X"), backgroundHex: "217346"
            )
        case "pdf":
            return DeliverableIconStyle(
                glyph: .symbol("doc.richtext.fill"),
                backgroundHex: "D92D20"
            )
        case "md", "txt", "rtf":
            return DeliverableIconStyle(
                glyph: .symbol("doc.text.fill"),
                backgroundHex: "5B6B7A"
            )
        case "html", "htm":
            return DeliverableIconStyle(
                glyph: .symbol("safari.fill"),
                backgroundHex: "1473C8"
            )
        case "zip", "7z", "tar", "gz":
            return DeliverableIconStyle(
                glyph: .symbol("archivebox.fill"),
                backgroundHex: "6E777D"
            )
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return DeliverableIconStyle(
                glyph: .symbol("photo.fill"),
                backgroundHex: "2E7D4F"
            )
        case "mp4", "mov", "m4v":
            return DeliverableIconStyle(
                glyph: .symbol("film.fill"), backgroundHex: "6A4FD0"
            )
        case "mp3", "wav", "m4a", "aac":
            return DeliverableIconStyle(
                glyph: .symbol("waveform"), backgroundHex: "C77400"
            )
        default:
            return DeliverableIconStyle(
                glyph: .symbol("doc.fill"), backgroundHex: "949B9F"
            )
        }
    }
}
