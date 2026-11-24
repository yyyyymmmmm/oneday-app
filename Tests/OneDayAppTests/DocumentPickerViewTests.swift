import SwiftUI
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import OneDayApp

/// §317 文件选择器状态旗呈现断言（诊断 attach-
/// noresponse-diagnosis-20261117 的 P1 竞速病换
/// 代后）：DocumentPickerView（representable）与
/// 相机行同制——
/// ①状态旗置真即经 fullScreenCover 呈现 UIDocu-
/// mentPickerViewController（多选口径与 delegate
/// 在场对账）；
/// ②单选配置（文件页入口口径）如实落到 picker；
/// ③coordinator 回调直通：选定交 URL 数组、取
/// 消交 onCancel（无中间静默出口）；
/// ④生产接力链：面板 sheet 收起 onDismiss 置文
/// 件旗 → 框架随后呈现 picker（afterAttachPan-
/// elDismiss 的登记→onDismiss→置旗全链在真窗
/// 口里成立，旧 450ms 睡眠竞速形态就此有回归哨）
@MainActor
final class DocumentPickerViewTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874

    private var window: UIWindow!

    override func tearDown() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - 装配工具

    private func assemble<Content: View>(
        content: Content
    ) -> UIViewController {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(
                x: 0, y: 0, width: windowW, height: windowH
            )
        } else {
            window = UIWindow(
                frame: CGRect(
                    x: 0, y: 0, width: windowW, height: windowH
                )
            )
        }
        let root = UIHostingController(rootView: content)
        window.rootViewController = root
        window.makeKeyAndVisible()
        return root
    }

    /// 泵主 runloop 直到条件成立或超时（呈现动画
    /// 在 runloop 上推进，静态读数等不到）
    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.1)
            )
        }
        return condition()
    }

    /// 在呈现层级里找 UIDocumentPickerViewContr-
    /// oller：representable 在 cover 内可能直呈、
    /// 也可能嵌在托管控制器子层，两路都收
    private func findPicker(
        in controller: UIViewController?
    ) -> UIDocumentPickerViewController? {
        guard let controller else { return nil }
        if let picker =
            controller as? UIDocumentPickerViewController
        {
            return picker
        }
        for child in controller.children {
            if let picker = findPicker(in: child) {
                return picker
            }
        }
        return findPicker(
            in: controller.presentedViewController
        )
    }

    // MARK: - ①② 状态旗呈现与配置

    private final class FlagModel: ObservableObject {
        @Published var presented = false
    }

    private struct FlagHost: View {
        @ObservedObject var model: FlagModel
        let allowsMultipleSelection: Bool

        var body: some View {
            Color.clear
                .fullScreenCover(
                    isPresented: $model.presented
                ) {
                    DocumentPickerView(
                        allowsMultipleSelection:
                            allowsMultipleSelection,
                        onPick: { _ in },
                        onCancel: {}
                    )
                }
        }
    }

    func testPickerPresentsViaStateFlagWithMultiSelection()
        throws
    {
        let model = FlagModel()
        let root = assemble(
            content: FlagHost(
                model: model, allowsMultipleSelection: true
            )
        )
        model.presented = true
        let picker = try XCTUnwrap(
            waitUntil { self.findPicker(in: root) != nil }
                ? findPicker(in: root) : nil,
            "状态旗置真后 picker 未在时限内呈现"
        )
        XCTAssertTrue(picker.allowsMultipleSelection)
        let delegate = try XCTUnwrap(
            picker.delegate,
            "picker delegate 未接 coordinator"
        )
        XCTAssertTrue(
            delegate is DocumentPickerView.Coordinator
        )
    }

    func testPickerRespectsSingleSelection() throws {
        let model = FlagModel()
        let root = assemble(
            content: FlagHost(
                model: model, allowsMultipleSelection: false
            )
        )
        model.presented = true
        let picker = try XCTUnwrap(
            waitUntil { self.findPicker(in: root) != nil }
                ? findPicker(in: root) : nil,
            "单选配置下 picker 未在时限内呈现"
        )
        XCTAssertFalse(picker.allowsMultipleSelection)
    }

    // MARK: - ③ coordinator 回调直通

    func testCoordinatorDeliversPickedURLs() {
        var picked: [URL]?
        let view = DocumentPickerView(
            onPick: { picked = $0 },
            onCancel: {}
        )
        let coordinator = view.makeCoordinator()
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item], asCopy: true
        )
        let url = URL(
            fileURLWithPath: "/tmp/docpicker-probe.txt"
        )
        coordinator.documentPicker(
            picker, didPickDocumentsAt: [url]
        )
        XCTAssertEqual(picked, [url])
    }

    func testCoordinatorDeliversCancel() {
        var cancelled = false
        let view = DocumentPickerView(
            onPick: { _ in },
            onCancel: { cancelled = true }
        )
        let coordinator = view.makeCoordinator()
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item], asCopy: true
        )
        coordinator.documentPickerWasCancelled(picker)
        XCTAssertTrue(cancelled)
    }

    // MARK: - ④ 面板收起接力链（生产形态）

    private final class ChainModel: ObservableObject {
        @Published var panelPresented = false
        @Published var pickerPresented = false
    }

    /// 与 ChatView 生产接线同构：附件面板 sheet
    /// 的 onDismiss 里置文件旗，picker 经 full-
    /// ScreenCover 随后呈现
    private struct ChainHost: View {
        @ObservedObject var model: ChainModel

        var body: some View {
            Color.clear
                .sheet(
                    isPresented: $model.panelPresented,
                    onDismiss: {
                        model.pickerPresented = true
                    }
                ) {
                    Text("面板替身")
                }
                .fullScreenCover(
                    isPresented: $model.pickerPresented
                ) {
                    DocumentPickerView(
                        onPick: { _ in },
                        onCancel: {}
                    )
                }
        }
    }

    func testPickerFollowsPanelDismissalViaOnDismiss()
        throws
    {
        let model = ChainModel()
        let root = assemble(content: ChainHost(model: model))
        model.panelPresented = true
        XCTAssertTrue(
            waitUntil {
                root.presentedViewController != nil
                    && self.findPicker(in: root) == nil
            },
            "面板 sheet 未在时限内呈现"
        )
        model.panelPresented = false
        let picker = try XCTUnwrap(
            waitUntil { self.findPicker(in: root) != nil }
                ? findPicker(in: root) : nil,
            "面板收起 onDismiss 置旗后 picker 未随后呈现"
                + "（接力链断裂）"
        )
        XCTAssertTrue(picker.allowsMultipleSelection)
    }
}
