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
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// 焦点桥：与 ChatView 的 @FocusState 双向同步
    ///（FocusState 的投影是其专属 Binding 类型）
    var isFocused: FocusState<Bool>.Binding
    /// 内容实测高（未封顶）回调：驱动多行形状判据
    var onMeasuredHeight: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.typingAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .body),
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
        placeholder.font = .preferredFont(forTextStyle: .body)
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
        // 焦点桥边沿触发：只在期望值相对上次已知状态变化时
        // 才驱动第一响应者。电平触发会在「UIKit 已聚焦、
        // delegate 回写未达」的窗口里被任意一次 SwiftUI 更新
        // 误伤 resign（0.2.7 首轮 CI 实证：点按聚焦被吃掉，
        // 键盘未起）；delegate 回调与 becomeFirstResponder
        // 同步发生，边沿记录后该窗口不存在
        let desired = isFocused.wrappedValue
        if desired != context.coordinator.lastFocus {
            context.coordinator.lastFocus = desired
            if desired, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !desired, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
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
        /// 焦点桥的上次已知状态（边沿触发用，见 updateUIView）
        var lastFocus = false
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            lastFocus = true
            parent.isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            lastFocus = false
            parent.isFocused.wrappedValue = false
        }
    }
}
