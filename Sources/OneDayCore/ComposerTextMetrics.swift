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
    /// 正文字体基准（.large 档）：16pt 系统字体——
    /// 0.2.9 定案的量测基准，本档下量测与排版与旧
    /// 固定口径逐字一致
    public static let basePointSize: CGFloat = 16

    /// 正文字体单一来源（0.43.0 无障碍专项 A11Y-D1
    /// 改版）：按 Dynamic Type 档位经 UIFontMetrics
    /// （.body 样式）缩放基准字体。0.2.9 的构造不
    /// 变——量测与渲染同读本口、同档取值，变的只是
    /// 字体本身随档缩放；旧「固定 16pt、不随档漂
    /// 移」口径防的是量测与排版各读一档的脱钩，本
    /// 改版以「档位自调用方显式贯穿量测链」取代之
    /// （视图取自身 traitCollection、布局取环境
    /// 档），见 DESIGN §112。无参口回当前档
    public static func bodyFont(
        for category: UIContentSizeCategory
    ) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: basePointSize),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: category
            )
        )
    }

    /// 当前档的正文字体（无参口：UITraitCollection
    /// .current——布局/绘制上下文中即 App 当前档）
    public static var bodyFont: UIFont {
        bodyFont(for: currentCategory)
    }

    /// 当前内容大小档（量测链无参口的统一回落源）
    public static var currentCategory: UIContentSizeCategory {
        UITraitCollection.current.preferredContentSizeCategory
    }

    // MARK: - 几何单一事实源（0.3.3，DESIGN-V4 §18）
    // 真机第 4/5 条定因方向：量测栈与视图排版栈的几何参
    // 数此前各写各的（inset/padding 在量测侧与视图侧分
    // 别字面），且 iOS 26 的 UITextView 默认排版栈与量测
    // 用的显式 TextKit-1 栈可能分家——光标矩形与行原点
    // 由视图的栈决定、行数由量测的栈决定，两栈不同源时
    // 「行数对、光标错位」。本节起几何只有这一份：量测
    // 容器、视图容器、占位符原点全读这里；视图由
    // makeTextView() 以显式 TextKit-1 栈构造，与量测同
    // 类同参（几何一致性由 ComposerGeometryTests 把守）。

    /// 文本容器内边距：零——间距由 SwiftUI 侧布局承担
    public static let textContainerInset: UIEdgeInsets = .zero
    /// 行片段内边距：零——行原点即 textOriginX
    public static let lineFragmentPadding: CGFloat = 0
    /// 文字左原点（视图坐标系）：inset.left＋padding＝0
    public static var textOriginX: CGFloat {
        textContainerInset.left + lineFragmentPadding
    }

    /// 视图工厂：以显式 TextKit-1 栈（Storage＋Layout-
    /// Manager＋Container）构造 UITextView 并施加统一几
    /// 何——视图排版栈与 lineCount 的量测栈同类同参
    public static func makeTextView() -> UITextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = UITextView(
            frame: .zero, textContainer: container
        )
        applyGeometry(to: textView)
        return textView
    }

    /// 统一几何施加（工厂与 updateUIView 兜底共用）：
    /// 字体/inset/padding/断行模式只许从本节出。字
    /// 体按视图自身 traitCollection 的档位取（视图
    /// 所在环境的档即排版档，A11Y-D1 贯穿口径）；
    /// adjustsFontForContentSizeCategory 同步打开作
    /// 系统侧兜底——档位变化时 updateUIView 的重申
    /// 仍是权威路径
    public static func applyGeometry(to textView: UITextView) {
        textView.font = bodyFont(
            for: textView.traitCollection.preferredContentSizeCategory
        )
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = textContainerInset
        textView.textContainer.lineFragmentPadding =
            lineFragmentPadding
        textView.textContainer.lineBreakMode = .byWordWrapping
    }

    /// 以给定宽度数文本行数。空文本按 1 行（空态口径与
    /// ComposerLayout.effectiveTextHeight 一致）。档
    /// 位决定量测字体（A11Y-D1）：量测档必须与排版
    /// 档同源，调用方有明确档时显式传、无参回当前档
    public static func lineCount(
        for text: String, width: CGFloat,
        category: UIContentSizeCategory = currentCategory
    ) -> Int {
        guard width > 0 else { return 1 }
        if text.isEmpty { return 1 }
        let storage = NSTextStorage(
            string: text,
            attributes: [.font: bodyFont(for: category)]
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(
                width: width, height: .greatestFiniteMagnitude
            )
        )
        container.lineFragmentPadding = lineFragmentPadding
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
        // 尾行补计（0.36.12，用户真机录屏定案，诊断档
        // composer-newline-diagnosis-20261110）：文本以
        // \n 结尾时，光标所在的那一空行是布局管理器的
        // extraLineFragment——字形区间长度为 0、不在上
        // 面的枚举范围内。此前漏数：「测试\n」数成 1
        // 行、胶囊不动，键入新字才跳高。口径：以 \n 结
        // 尾即 +1，光标行恒计入（「a\n\n」枚举 2 补后
        // 3、「\n」枚举 1 补后 2，语义皆正确）
        if text.hasSuffix("\n") { lines += 1 }
        return max(lines, 1)
    }

    /// 文本高＝行数 × 同档行高（行高与字体的同源一
    /// 致性由单测把守，见 ComposerLayout.lineHeight
    /// (for:) 的派生口径）
    public static func textHeight(
        for text: String, width: CGFloat,
        category: UIContentSizeCategory = currentCategory
    ) -> CGFloat {
        CGFloat(lineCount(for: text, width: width, category: category))
            * ComposerLayout.lineHeight(for: category)
    }

    /// 胶囊总高：只经 ComposerLayout 纯函数。入参为容器
    /// 宽——内部按单行窄宽与多行全宽各量一次（形态判据
    /// 恒走窄宽、全高走全宽，见 ComposerLayout 注）
    public static func capsuleHeight(
        for text: String, containerWidth: CGFloat,
        category: UIContentSizeCategory = currentCategory
    ) -> CGFloat {
        ComposerLayout.capsuleHeight(
            narrowMeasured: textHeight(
                for: text,
                width: ComposerLayout.textWidth(
                    forContainerWidth: containerWidth
                ),
                category: category
            ),
            fullMeasured: textHeight(
                for: text,
                width: ComposerLayout.textWidth(
                    forContainerWidth: containerWidth, multiline: true
                ),
                category: category
            ),
            category: category
        )
    }
}
