import UIKit

/// 发送舱文本量测（0.2.9 纯逻辑定案，DESIGN-V4 §13）：
/// 行数由 TextKit（NSLayoutManager）在与实际布局完全相
/// 同的字体与宽度下数出，胶囊高只由 ComposerLayout 纯
/// 函数决定——高度链上不存在第二权威。
///
/// 同源的构造：①字体单一来源在此，ComposerTextView 的
/// 正文字体取自这里，量测与渲染共用同一 UIFont；②宽度
/// 同源——文本视图的实际布局宽＝容器宽 − ComposerLayout
/// .horizontalChrome（132，逐项对应 ChatView 的边距与
/// 键宽定义），sizeThatFits 把布局提议宽原样喂给本量
/// 测，量测宽≡布局宽，不存在另一套宽度；③排版参数与
/// 文本视图本体一致（lineFragmentPadding 0、无容器内边
/// 距、按词缠绕），数出的行数就是视图里渲染的行数。
public enum ComposerTextMetrics {
    /// 正文字体单一来源（固定 16pt 系统字体，不随
    /// Dynamic Type 漂移——量测口径与排版口径同源）
    public static var bodyFont: UIFont { .systemFont(ofSize: 16) }

    /// 以给定宽度数文本行数。空文本按 1 行（空态口径与
    /// ComposerLayout.effectiveTextHeight 一致）
    public static func lineCount(for text: String, width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        if text.isEmpty { return 1 }
        let storage = NSTextStorage(
            string: text, attributes: [.font: bodyFont]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(
                width: width, height: .greatestFiniteMagnitude
            )
        )
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        layoutManager.ensureLayout(for: container)
        var lines = 0
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(
                location: 0, length: layoutManager.numberOfGlyphs
            )
        ) { _, _, _, _, _ in lines += 1 }
        return max(lines, 1)
    }

    /// 文本高＝行数 × ComposerLayout.lineHeight（行高常
    /// 数与 bodyFont.lineHeight 的一致性由单测把守）
    public static func textHeight(for text: String, width: CGFloat) -> CGFloat {
        CGFloat(lineCount(for: text, width: width))
            * ComposerLayout.lineHeight
    }

    /// 胶囊总高：只经 ComposerLayout 纯函数（单行基数
    /// 46、多行随行递增、6 行封顶）
    public static func capsuleHeight(for text: String, width: CGFloat) -> CGFloat {
        ComposerLayout.capsuleHeight(
            measured: textHeight(for: text, width: width)
        )
    }
}
