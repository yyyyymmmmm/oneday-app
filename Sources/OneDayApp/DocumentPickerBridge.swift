import UIKit
import UniformTypeIdentifiers

/// 文件选择 UIKit 桥（0.36.31 件二换桥）：聊天页
/// 「选文件」不再走 SwiftUI `.fileImporter`——它在
/// 侧载设备类（万能签／TrollStore／Sideloadly 同
/// 类）上点「打开」毫无反应：picker 被呈现在正被
/// 拆毁的 SwiftUI 呈现上下文上、coordinator 已
/// 死、delegate 永不触发（不关闭、无结果、无报
/// 错；外部同形生产实证 LunWhale/minis-open 提交
/// e13e4b1 逐字定案，本仓诊断 file-picker-batch-
/// diagnosis-20261111）。本桥照公认修法形态：
/// UIDocumentPickerViewController 自当前最顶层
/// VC 呈现、绕开 SwiftUI coordinator；coordina-
/// tor 静态强持有到 picker 关闭；呈现延一拍避开
/// Menu 收起瞬间；回调先 dismiss 再把 URL 数组
/// 交回业务层（ChatView.loadPickedFiles）。
/// asCopy: true——系统先把所选文件拷进 App 临时
/// 区再交 URL，副本在本 App 容器内、读取无需安
/// 全作用域（旧 .fileImporter 路的安全作用域起停
/// 配对随之退役）；多选保留、类型 [.item] 不变。
enum DocumentPickerBridge {

    /// coordinator 静态强持有：picker 的 delegate
    /// 是弱引用，present 返回后若无人持有 coordi-
    /// nator，回调永远不会来——持有到选定/取消为
    /// 止，关闭时在回调里释放
    private static var retainedCoordinator: Coordinator?

    static func present(onPick: @escaping ([URL]) -> Void) {
        // 延一拍：等触发它的 Menu 收起落定再呈现，
        // 不与 dismissal 同拍撞车（minis-open 的
        // DeferredPresentation 同口径）
        Task { @MainActor in
            guard let presenter = topmostViewController() else {
                return
            }
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item], asCopy: true
            )
            picker.allowsMultipleSelection = true
            let coordinator = Coordinator(onPick: onPick)
            picker.delegate = coordinator
            retainedCoordinator = coordinator
            presenter.present(picker, animated: true)
        }
    }

    /// 沿 presentedViewController 链走到当前最顶层
    /// VC（干净的呈现上下文，不借道任何 SwiftUI
    /// 呈现修饰符的宿主）
    private static func topmostViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let keyWindow = windows.first { $0.isKeyWindow } ?? windows.first
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private static func releaseCoordinator() {
        retainedCoordinator = nil
    }

    private final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            // 先 dismiss 再交回：业务层随后的状态变
            // 更（附件入条）不与 picker 收起同帧打架
            controller.dismiss(animated: true)
            DocumentPickerBridge.releaseCoordinator()
            onPick(urls)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            // 用户主动取消不打扰、无声收尾（P-18 的
            // 有声口径管的是失败出口，不是取消）
            DocumentPickerBridge.releaseCoordinator()
        }
    }
}
