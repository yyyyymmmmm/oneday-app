import OneDayCore
import SwiftUI
import UIKit

/// 0.2.7 发送舱文本视图（DESIGN-V4 §11）：自量高 UITextView。
///
/// 换代缘由（§11.1 定案）：0.2.6 的纵向 TextField 是发送舱
/// 高度链上唯一没有权威量高者的一环——其理想高由 SwiftUI
/// 与内嵌可滚动 UITextView 协商产生，链上其余各环的
/// fixedSize 只把子视图理想高原样上传。真机键盘升起的
/// 安全区重排＋拼音 marked text 组合期间，该协商把 2 行
/// 文字的理想高贪大至上限量级（真机截图量测盒高约 140pt，
/// 文字仅 2 行），整舱随之膨胀、两键被 HStack(.bottom)
/// 钉在盒底、首行顶在盒顶——撕裂空盒。模拟器布局通道不
/// 产生该提议，三路构造均不复现。
/// 改走成熟聊天库的量高架构（Exyte/Chat 与 InputBar-
/// AccessoryView 的 InputTextView 一脉）：高度只有一个
/// 权威来源——文本布局本身。
/// 0.2.9 纯逻辑定案（DESIGN-V4 §13）：行数由 OneDayCore
/// 的 ComposerTextMetrics 以 TextKit（NSLayoutManager）
/// 在与实际布局完全相同的字体（单一来源 bodyFont）与
/// 宽度（sizeThatFits 的布局提议宽）下数出，胶囊高只
/// 由 ComposerLayout 纯函数决定（单测把守）；玻璃行高
/// ＝本视图高＋固定边距，不存在第二方提议能把盒子撑开。
///
/// 0.2.8 焦点拆桥（DESIGN-V4 §12）：0.2.7 的 @FocusState
/// 边沿桥是真机「点输入框键盘弹不出」的定案元凶——UIKit
/// 原生聚焦必须先经 SwiftUI 焦点状态往返批准，而 SwiftUI
/// 焦点引擎对层级内第一响应者有自己的仲裁，representable
/// 在引擎图外成为第一响应者会被其账面值顶掉（前任三轮 CI
/// 在命中路径已干净后仍聚焦不能、真机同症）。本版起聚焦
/// 只走 UIKit 原生通道：点按由文本视图自己 becomeFirst-
/// Responder，SwiftUI 侧状态仅经 delegate 回调观察回写、
/// 不把关；程序化收起/聚焦经 ComposerFocusHandle 直达
/// 文本视图。文本视图是自身区域内最上层的可交互元素，
/// 它与手指之间不隔任何手势与覆盖层（审计全文 §12.1）。
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// 程序化焦点句柄：makeUIView 时登记文本视图本体，
    /// ChatView 经它收起键盘/演示自检聚焦，不经 SwiftUI 状态
    var focusHandle: ComposerFocusHandle
    /// 焦点观察回调（delegate 回写，只观察不把关）
    var onFocusChange: (Bool) -> Void
    /// 光标 caret 色（0.3.4，§19 变/不变表：caret 属
    /// 「跟主题变」一侧——由 ChatView 传入强调色令牌的
    /// UIKit 形态；输入框填充/边框则归中性，两事分开）
    var caretColor: UIColor
    // 0.3.3：onMeasuredHeight 通道撤销——多行形态判据改
    // 由布局层（ChatView.ComposerBarLayout）以 sizeThat-
    // Fits 量测回写，视图不再反向驱动布局状态

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 正文口径：固定 16pt 系统字体——与 Muse 输入行看
    /// 齐（其文字行约 20pt）。字体单一来源在 OneDayCore
    /// 的 ComposerTextMetrics（量测与渲染共用，不许在此
    /// 另立一份）；ComposerLayout.lineHeight=19.17 是该
    /// 字体的实测行高、与 bodyFont.lineHeight 的一致性
    /// 由单测把守（§13）。不再跟随 Dynamic Type 放大，
    /// 否则单行规格随系统字号档漂移、量高与排版脱钩
    private static var bodyFont: UIFont { ComposerTextMetrics.bodyFont }

    func makeUIView(context: Context) -> UITextView {
        // 0.3.3 工厂构造：以显式 TextKit-1 栈建视图并施
        // 加统一几何（ComposerTextMetrics.makeTextView，
        // 与量测栈同类同参——治光标逃逸/换行不对齐的
        // 几何同源，见该文件几何节与 §18）
        let textView = ComposerTextMetrics.makeTextView()
        textView.delegate = context.coordinator
        // 可编辑与可交互是默认值，此处显式写死（§12.1 审计
        // 项④：配置层不给聚焦留任何含糊）
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.typingAttributes = [
            .font: Self.bodyFont,
            .foregroundColor: UIColor.label,
        ]
        textView.isScrollEnabled = false
        textView.tintColor = caretColor
        textView.accessibilityIdentifier = "composerField"
        textView.text = text
        // 占位符：UITextView 没有占位符，用子 UILabel 承担
        // （经典 InputTextView 做法）。0.2.7 首轮曾以 SwiftUI
        // .overlay 盖在 representable 上——CI 实证点按聚焦被
        // 吃掉（field.tap 后键盘未起、焦点未获），占位层回
        // 视图内部后命中路径上再无外来层；UILabel 默认不
        // 接收触摸，亦显式关闭
        let placeholder = UILabel()
        placeholder.text = "发消息…"
        placeholder.font = Self.bodyFont
        placeholder.textColor = .tertiaryLabel
        placeholder.isUserInteractionEnabled = false
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            // 0.3.3：占位符原点走几何单一事实源（此前手
            // 写 constant 1 与量测口径是两套账）
            placeholder.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor,
                constant: ComposerTextMetrics.textOriginX
            ),
            placeholder.topAnchor.constraint(
                equalTo: textView.topAnchor,
                constant: ComposerTextMetrics.textContainerInset.top
            ),
        ])
        context.coordinator.placeholderLabel = placeholder
        placeholder.isHidden = !(text.isEmpty)
        // 登记进焦点句柄：程序化聚焦/收起从此直达本体
        focusHandle.attach(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        // 组合输入（marked text）进行中不回写，避免打断 IME
        if textView.text != text, textView.markedTextRange == nil {
            textView.text = text
        }
        context.coordinator.placeholderLabel?.isHidden =
            !(textView.text?.isEmpty ?? true)
        // 0.3.3 几何兜底：每次更新重申统一几何（防系统
        // 在重排/旋转时改回默认 inset/padding）
        ComposerTextMetrics.applyGeometry(to: textView)
        // 主题切换时 caret 跟随新强调色（0.3.4）
        textView.tintColor = caretColor
        // 0.2.8：updateUIView 不再碰第一响应者（焦点桥已拆，
        // 见文件头注）。聚焦/失焦只由 UIKit 原生通道与
        // focusHandle 决定，SwiftUI 更新永不批准也不驳回
        refreshScroll(textView)
    }

    /// 高度权威（0.2.9 纯逻辑定案，§13）：行数由
    /// ComposerTextMetrics 以 TextKit 在提议宽（＝实际布
    /// 局宽）与单一来源字体下数出（含 marked 段——组合
    /// 文本同在 textView.text 里，与 IME 同路），高度只
    /// 经 ComposerLayout 纯函数封顶。0.3.3：本函数只回
    /// 高、不再回调报模式——模式由布局层据两次
    /// sizeThatFits（窄宽/全宽）自行判定
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView textView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let reported = ComposerTextMetrics.textHeight(
            for: textView.text ?? "", width: width
        )
        return CGSize(
            width: width,
            height: ComposerLayout.cappedTextHeight(measured: reported)
        )
    }

    /// 过上限才内滚（在文本变化与回写时刷新，不在量高里改状态）
    private func refreshScroll(_ textView: UITextView) {
        guard textView.bounds.width > 0 else { return }
        let fitted = ComposerTextMetrics.textHeight(
            for: textView.text ?? "", width: textView.bounds.width
        )
        textView.isScrollEnabled =
            ComposerLayout.shouldScroll(measured: fitted)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView
        /// 占位符子标签（makeUIView 时挂上）
        weak var placeholderLabel: UILabel?

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // marked 段同样回写绑定：与 SwiftUI TextField 的
            // 行为一致（组合中发送键即亮，见真机截图口径）
            parent.text = textView.text ?? ""
            placeholderLabel?.isHidden = !(textView.text.isEmpty)
            parent.refreshScroll(textView)
        }

        // 焦点只观察回写（0.2.8 拆桥）：delegate 是事实源，
        // SwiftUI 侧状态跟随它变，不反过来批准它
        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }
    }
}

/// 发送舱焦点句柄（0.2.8）：ChatView 与文本视图本体之间
/// 的程序化焦点通道——收起键盘（点消息区空白）与演示模
/// 式程序化聚焦自检都经它直达 UITextView，不经任何
/// SwiftUI 焦点状态。视图未就绪时先记 pending，登记时补上。
final class ComposerFocusHandle {
    private weak var textView: UITextView?
    private var pendingFocus = false

    func attach(_ textView: UITextView) {
        self.textView = textView
        if pendingFocus {
            pendingFocus = false
            textView.becomeFirstResponder()
        }
    }

    func focus() {
        if let textView {
            textView.becomeFirstResponder()
        } else {
            pendingFocus = true
        }
    }

    func dismiss() {
        textView?.resignFirstResponder()
    }
}
