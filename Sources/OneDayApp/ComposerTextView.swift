import SwiftUI
import UIKit

/// 0.2.7 发送舱文本视图（DESIGN-V4 §11）：自量高 UITextView。
///
/// 换代缘由：SwiftUI 的纵向 TextField（底层 UITextView 被嵌
/// 在 SwiftUI 的尺寸提议协商里）在真机「键盘＋拼音 marked
/// text」组合态下被撑成约 139pt 的撕裂空盒（首行顶盒顶、
/// 编辑行掉盒底），而模拟器以三种构造（编程 marked text×
/// 默认玻璃/裸玻璃两路、真实拼音键盘＋候选条）逐环量测均
/// 不复现——提议协商的结果依赖真机布局通道，无从在本地
/// 锁死。改走成熟聊天库（InputBarAccessoryView 的
/// InputTextView 一脉）的架构：高度只有一个权威来源——
/// 文本视图自己的布局管理器。sizeThatFits 以提议宽度量
/// 当前文本（含 marked 段，与 IME 同路）的真实行高，上限
/// 6 行封顶后内滚；玻璃行的高＝本视图高＋固定边距，逐字
/// 决定，不存在第二方提议能把盒子撑开或撕裂。
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    /// 焦点桥：与 ChatView 的 @FocusState 双向同步
    ///（FocusState 的投影是其专属 Binding 类型）
    var isFocused: FocusState<Bool>.Binding
    /// 内容实测高（未封顶）回调：驱动多行形状判据
    var onMeasuredHeight: (CGFloat) -> Void

    /// 6 行封顶（正文行高约 22.5pt）
    private static var maxTextHeight: CGFloat { 22.5 * 6 }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = ProbeTextView()
        print("[DIAG] ComposerTextView makeUIView")
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

    /// 高度权威：以提议宽度量文本真实高度，6 行封顶
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
            height: min(fitted.height, Self.maxTextHeight)
        )
    }

    /// 过上限才内滚（在文本变化与回写时刷新，不在量高里改状态）
    private func refreshScroll(_ textView: UITextView) {
        guard textView.bounds.width > 0 else { return }
        let fitted = textView.sizeThatFits(
            CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        )
        textView.isScrollEnabled = fitted.height > Self.maxTextHeight
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
            print("[DIAG] textViewDidBeginEditing")
            lastFocus = true
            parent.isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            lastFocus = false
            parent.isFocused.wrappedValue = false
        }
    }
}

/// 0.2.7 临时诊断（定位点按不聚焦，定案后删）：把命中与
/// 聚焦路径的每一站都打出来——point(inside:) 是否被问、
/// touches 是否到达、becomeFirstResponder 的返回值
final class ProbeTextView: UITextView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let result = super.point(inside: point, with: event)
        print("[DIAG] point(inside: \(point)) -> \(result)")
        return result
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("[DIAG] touchesBegan count=\(touches.count)")
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("[DIAG] touchesEnded")
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("[DIAG] touchesCancelled")
        super.touchesCancelled(touches, with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        print("[DIAG] becomeFirstResponder -> \(result)")
        return result
    }
}
