import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 文件选择呈现（§317 换代）：UIDocumentPicker-
/// ViewController 的 UIViewControllerRepresen-
/// table 包装，与同面板相机行 CameraPicker 同
/// 构——宿主以状态旗（isPresented）驱动 .full-
/// ScreenCover 呈现，SwiftUI 框架在附件面板
/// sheet 收起后排队呈现，不经任何命令式 pre-
/// sent、不靠延时猜收起完成。
///
/// 换代史：0.36.31 因 `.fileImporter` 在侧载设
/// 备类上 delegate 永不触发（诊断 file-picker-
/// batch-diagnosis-20261111：死的是 fileImpor-
/// ter 自己的内部 coordinator，不是状态旗呈现
/// 本身）换命令式 DocumentPickerBridge（顶层
/// VC 直 present）；该桥靠调用方固定睡 450ms
/// 避收起竞速，iOS 26 收起时长非常量，睡醒收
/// 起未完时 present 被 UIKit 静默丢弃——「添
/// 加文件」面板收了选择器永不来（诊断 attach-
/// noresponse-diagnosis-20261117）。§317 核查
/// 定档：被判死的是 `.fileImporter` 这一具体修
/// 饰符，representable＋状态旗路在本仓有生产
/// 实证（CameraPicker 同设备类长期在役）、无
/// 平台硬约束禁止 UIDocumentPicker 走 repre-
/// sentable 托管，故文件行回归与相机/选图行同
/// 一条框架排队呈现路，命令式桥整件退役；桥的
/// 全出口留痕口径平移至本件（呈现/选定/取消各
/// 落 ChatDiagTrace 一条，不许无声）。
/// asCopy: true 沿旧桥口径——系统先把所选文件
/// 拷进 App 临时区再交 URL，副本在本 App 容器
/// 内、读取无需安全作用域；类型 [.item] 不变，
/// 多选由宿主按入口口径配置（聊天多选、文件
/// 页单选）
struct DocumentPickerView: UIViewControllerRepresentable {
    var allowsMultipleSelection: Bool = true
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(
        context: Context
    ) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item], asCopy: true
        )
        picker.allowsMultipleSelection =
            allowsMultipleSelection
        picker.delegate = context.coordinator
        // 呈现出口留痕：makeUIViewController 即框
        // 架起呈现的一拍（§317 全出口留痕口径）
        ChatDiagTrace.record("docpicker 已呈现（状态旗排队呈现）")
        return picker
    }

    func updateUIViewController(
        _ controller: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject,
        UIDocumentPickerDelegate
    {
        let parent: DocumentPickerView

        init(parent: DocumentPickerView) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            ChatDiagTrace.record(
                "docpicker 已选定 \(urls.count) 个文件"
            )
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(
            _ controller: UIDocumentPickerViewController
        ) {
            // 用户主动取消不打扰用户，但留痕归档
            // （§317 全出口留痕口径，取消非失败）
            ChatDiagTrace.record("docpicker 用户取消")
            parent.onCancel()
        }
    }
}
