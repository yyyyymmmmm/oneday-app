import SwiftUI
import OneDayCore

/// 扁平类型图标（§452.4）：程序绘制、零图片资源——
/// 生成法学 Telegram-iOS（ChatMessageInteractive-
/// FileNode 的已下载态用主题程序图形、无图片文件），
/// 形态学微信/WPS 式（扁平文档形＋折角＋白色粗体短
/// 标、纯色块），家族分类走 Core DeliverableIcon-
/// Style 单源。§128 的 3D 黏土 PNG 套就此退役（资产
/// 留仓、渲染不再引用）：扁平、克制、专业，零立体、
/// 零表情包味（用户 2026-11-24 03:27 定调）。
struct FileTypeIconView: View {
    let fileName: String
    var isDirectory: Bool = false
    /// 图标高（文档形宽 = 高 × 0.78）
    var height: CGFloat = 40

    private var style: DeliverableIconStyle {
        DeliverableIconStyle.style(
            forFileName: fileName, isDirectory: isDirectory
        )
    }

    private var width: CGFloat { height * 0.78 }

    var body: some View {
        let slug = style.slug
        Group {
            if slug == "folder" || slug == "folder-open" {
                folderBody
            } else {
                docBody(slug: slug)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    // MARK: 文档形

    private func docBody(slug: String) -> some View {
        let palette = Self.palette(for: slug)
        let fold = height * 0.24
        return ZStack {
            DocShape(fold: fold)
                .fill(palette.base)
            DocFoldShape(fold: fold)
                .fill(palette.fold)
            label(slug: slug)
                .padding(.top, fold * 0.55)
        }
    }

    @ViewBuilder
    private func label(slug: String) -> some View {
        if let symbol = Self.symbol(for: slug) {
            Image(systemName: symbol)
                .font(.system(size: height * 0.30, weight: .bold))
                .foregroundStyle(.white)
        } else {
            Text(Self.labelText(for: slug, fileName: fileName))
                .font(.system(
                    size: Self.labelText(for: slug, fileName: fileName).count > 2
                        ? height * 0.185 : height * 0.30,
                    weight: .bold, design: .rounded
                ))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, width * 0.08)
        }
    }

    // MARK: 文件夹形

    private var folderBody: some View {
        let palette = Self.palette(for: "folder")
        return ZStack {
            FolderShape()
                .fill(palette.fold)
            FolderFrontShape()
                .fill(palette.base)
        }
    }

    // MARK: 家族色与短标（§452.4 定版表）

    struct Palette {
        let base: Color
        let fold: Color
    }

    static func palette(for slug: String) -> Palette {
        switch slug {
        case "pdf":
            return Palette(base: Color(hex: 0xD93A3A), fold: Color(hex: 0xB92C2C))
        case "word":
            return Palette(base: Color(hex: 0x4A7DC9), fold: Color(hex: 0x3A67AB))
        case "sheet":
            return Palette(base: Color(hex: 0x35A05A), fold: Color(hex: 0x2A8549))
        case "slides":
            return Palette(base: Color(hex: 0xE2703A), fold: Color(hex: 0xC75B2C))
        case "archive":
            return Palette(base: Color(hex: 0xA97B2F), fold: Color(hex: 0x8F6624))
        case "image":
            return Palette(base: Color(hex: 0x7D6BC4), fold: Color(hex: 0x6655AC))
        case "video":
            return Palette(base: Color(hex: 0x5856D6), fold: Color(hex: 0x4644B8))
        case "audio":
            return Palette(base: Color(hex: 0xC94F6D), fold: Color(hex: 0xAB3E58))
        case "text":
            return Palette(base: Color(hex: 0x64748B), fold: Color(hex: 0x52627A))
        case "code":
            return Palette(base: Color(hex: 0x2A9D8F), fold: Color(hex: 0x218276))
        case "app":
            return Palette(base: Color(hex: 0x5A5A5E), fold: Color(hex: 0x48484B))
        case "folder", "folder-open":
            return Palette(base: Color(hex: 0xEFC65C), fold: Color(hex: 0xE3B341))
        case "document":
            return Palette(base: Color(hex: 0x8A8D93), fold: Color(hex: 0x74777D))
        default:
            return Palette(base: Color(hex: 0x9A9AA0), fold: Color(hex: 0x838388))
        }
    }

    /// 字形短标（WPS 式单字/扩展名）；有 SF 字形者走
    /// symbol 不走文字
    static func labelText(for slug: String, fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension
            .uppercased()
        switch slug {
        case "pdf": return "PDF"
        case "word": return "W"
        case "sheet": return "X"
        case "slides": return "P"
        case "text": return ext.isEmpty ? "TXT" : ext
        case "code": return "</>"
        case "archive": return ext.isEmpty ? "ZIP" : ext
        case "document": return ext.isEmpty ? "DOC" : ext
        case "unknown": return "?"
        default: return ext.isEmpty ? "?" : ext
        }
    }

    static func symbol(for slug: String) -> String? {
        switch slug {
        case "image": return "photo.fill"
        case "video": return "play.fill"
        case "audio": return "music.note"
        case "app": return "square.grid.2x2.fill"
        default: return nil
        }
    }
}

/// 文档形：圆角矩形＋右上折角切口
private struct DocShape: Shape {
    let fold: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.13
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(0),
            endAngle: .degrees(90), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90),
            endAngle: .degrees(180), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r, startAngle: .degrees(180),
            endAngle: .degrees(270), clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

/// 折角三角（深一档同色）
private struct DocFoldShape: Shape {
    let fold: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        p.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        p.closeSubpath()
        return p
    }
}

/// 文件夹：后板（带耳）＋前板（扁平两层）
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width * 0.09
        var p = Path()
        let tabW = rect.width * 0.42
        let tabTop = rect.minY + rect.height * 0.10
        p.move(to: CGPoint(x: rect.minX + r, y: tabTop))
        p.addLine(to: CGPoint(x: rect.minX + tabW - r, y: tabTop))
        p.addArc(
            center: CGPoint(x: rect.minX + tabW - r, y: tabTop + r),
            radius: r, startAngle: .degrees(270),
            endAngle: .degrees(0), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + tabW + r, y: rect.minY + rect.height * 0.30))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.30))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct FolderFrontShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width * 0.09
        var p = Path()
        let top = rect.minY + rect.height * 0.34
        p.move(to: CGPoint(x: rect.minX + r, y: top))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: top + r),
            radius: r, startAngle: .degrees(270),
            endAngle: .degrees(0), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(0),
            endAngle: .degrees(90), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90),
            endAngle: .degrees(180), clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX, y: top + r))
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: top + r),
            radius: r, startAngle: .degrees(180),
            endAngle: .degrees(270), clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

