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
/// 权威来源——文本视图自己的布局管理器。sizeThatFits
/// 以提议宽度量当前文本（含 marked 段，与 IME 同路）的
/// 真实行高，封顶／内滚／形状判据的算术归 OneDayCore
/// 的 ComposerLayout 纯逻辑（单测把守）；玻璃行高＝本
/// 视图高＋固定边距，不存在第二方提议能把盒子撑开。
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
    /// 内容实测高（未封顶）回调：驱动多行形状判据
    var onMeasuredHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 正文口径（0.2.8，DESIGN-V4 §12.3）：固定 16pt 系统
    /// 字体——与 Muse 输入行看齐（其文字行约 20pt）；
    /// ComposerLayout.lineHeight=19.17 是该字体的 CI 帧实
    /// 测行高（0.2.9 校准，§13.2），与此同口径。
    /// 不再跟随 Dynamic Type 放大，否则单行规格随系统字
    /// 号档漂移、量高口径与排版口径脱钩
    private static var bodyFont: UIFont { .systemFont(ofSize: 16) }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        // 可编辑与可交互是默认值，此处显式写死（§12.1 审计
        // 项④：配置层不给聚焦留任何含糊）
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.font = Self.bodyFont
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.typingAttributes = [
            .font: Self.bodyFont,
            .foregroundColor: UIColor.label,
        ]
        // 内边距归零：间距由 SwiftUI 侧 padding 统一承担，
        // 量高口径与排版口径一致
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.isScrollEnabled = false
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
            placeholder.leadingAnchor.constraint(
                equalTo: textView.leadingAnchor, constant: 1
            ),
            placeholder.topAnchor.constraint(
                equalTo: textView.topAnchor
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
        // 0.2.8：updateUIView 不再碰第一响应者（焦点桥已拆，
        // 见文件头注）。聚焦/失焦只由 UIKit 原生通道与
        // focusHandle 决定，SwiftUI 更新永不批准也不驳回
        refreshScroll(textView)
    }

    /// 高度权威：以提议宽度量文本真实高度（含 marked 段），
    /// 封顶口径走 ComposerLayout；未封顶实测值另行回调，
    /// 供 ChatView 判多行形状
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView textView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let fitted = textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let reported = fitted.height
        DispatchQueue.main.async {
            onMeasuredHeight(reported)
        }
        return CGSize(
            width: width,
            height: ComposerLayout.cappedTextHeight(measured: fitted.height)
        )
    }

    /// 过上限才内滚（在文本变化与回写时刷新，不在量高里改状态）
    private func refreshScroll(_ textView: UITextView) {
        guard textView.bounds.width > 0 else { return }
        let fitted = textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        )
        textView.isScrollEnabled =
            ComposerLayout.shouldScroll(measured: fitted.height)
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
