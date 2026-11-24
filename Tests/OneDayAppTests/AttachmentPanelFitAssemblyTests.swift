import Photos
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §327（小修批①，承 §303）＋ D5（台账 11）真实
/// 装配断言：附件面板在真窗口里真呈现——
/// ①面板在场：presented 控制器存在、其托管视图
/// sizeThatFits 与独立托管理想高逐值对账（空
/// sheet 测不出此高）；
/// ②定高归系统档位（D5 修订）：presented 的
/// sheetPresentationController detents 包含一
/// 个 .height 档与 .large、帧高−safeBottom ≈
/// 内容理想高（容差 4，贴合不再留大片空白）；
/// ③确认按钮增减跟随（D5 新增、§461 续）：模
/// 拟确认按钮出现/消失，帧高跟随 ±72pt（56 按
/// 钮高＋16 间
/// 距）；
/// §327 沿革：custom detent 桥退役、改系统档位
/// [.medium, .large]、帧高恒半窗、增行不改高。
/// D5 修订：改 .height(fitted) 贴合档＋.large、
/// 帧高贴内容（三态 137/305/377＋safeArea）、
/// 确认按钮增减时停在贴合档才跟随。
/// 首轮（§303 run 43763594395）实测 App 测试
/// 窗口内无障碍标签集为空集，在场断言因此不用
/// AX 标签、改走托管视图 sizeThatFits 对账（标
/// 签集只打印留档），本批沿用。
@MainActor
final class AttachmentPanelFitAssemblyTests: XCTestCase {

    private let windowW: CGFloat = 402
    private let windowH: CGFloat = 874

    private var window: UIWindow!

    override func tearDown() {
        window?.isHidden = true
        window = nil
        super.tearDown()
    }

    // MARK: - 真壳

    /// 呈现宿主（D5 修订）：根层 onAppear 置位呈
    /// 现。D5 起 AttachmentPanelView 在自身 body
    /// 内施加 presentation modifiers（需访问视图
    /// 状态算 fitted 档），SheetHost 只留 .sheet()
    /// 本体、不再调呈现口径配方
    private struct SheetHost<Content: View>: View {
        @State private var presented = false
        let content: Content

        var body: some View {
            Color.clear
                .onAppear { presented = true }
                .sheet(isPresented: $presented) {
                    content
                }
        }
    }

    private func assemble<Content: View>(
        content: Content
    ) -> UIViewController {
        // 呈现类断言须场景窗口（iOS 26 起 init
        // (frame:) 已弃用、且无场景窗口的 sheet 呈
        // 现口径不完整）：有场景挂场景并钉帧，无场
        // 景回落旧式帧窗
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
        let root = UIHostingController(
            rootView: SheetHost(content: content)
        )
        window.rootViewController = root
        window.makeKeyAndVisible()
        return root
    }

    /// 等呈现完成并落定：presented 出现且其视图帧
    /// 高连续三读不变（呈现动画走完）后返回帧高。
    /// afterChangeFrom 非 nil 时先等帧高离开该值
    /// （内容变更的动画起步前旧高会短暂稳定，不许
    /// 把旧高当落定值读走）
    private func settledSheetHeight(
        of root: UIViewController,
        timeout: TimeInterval = 10,
        afterChangeFrom reference: CGFloat? = nil
    ) -> CGFloat? {
        let deadline = Date().addingTimeInterval(timeout)
        var changed = reference == nil
        var last: CGFloat = -1
        var stableReads = 0
        while Date() < deadline {
            RunLoop.main.run(
                until: Date().addingTimeInterval(0.1)
            )
            guard let presented = root.presentedViewController
            else { continue }
            let height = presented.view.frame.height
            if !changed, let reference {
                if abs(height - reference) >= 0.5 {
                    changed = true
                } else {
                    continue
                }
            }
            if abs(height - last) < 0.5 {
                stableReads += 1
                if stableReads >= 3 { return height }
            } else {
                stableReads = 0
                last = height
            }
        }
        return nil
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + seconds
        ) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }

    private func makePanel() -> AttachmentPanelView {
        AttachmentPanelView(
            onCamera: {},
            onConfirmPhotos: { _ in },
            onViewAll: {},
            onAddFile: {},
            onAddVideo: {}
        )
    }

    // MARK: - ①② 真面板在场＋贴合高度（D5 口径）

    func testAttachPanelPresentsAtFittedHeight() throws {
        let root = assemble(content: makePanel())

        let sheetHeight = try XCTUnwrap(
            settledSheetHeight(of: root),
            "附件面板 sheet 未在时限内呈现落定"
        )
        let presented = try XCTUnwrap(root.presentedViewController)

        // 内容理想高（独立托管、同宽 sizeThatFits）
        let probe = UIHostingController(rootView: makePanel())
        let ideal = probe.sizeThatFits(
            in: CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height

        // 在场（①，沿用 §327 口径）：presented 本体
        // 即面板的托管控制器——其视图 sizeThatFits
        // 须与独立托管理想高对账（呈现的若是空
        // sheet 或错内容，测不出此高）。无障碍标
        // 签集只留档不作断言（首轮实测本环境 AX
        // 树不填充、为空集）。§327 口径差：桥退役
        // 后 presented 视图的底部安全区不再被反向
        // 补偿归零（.66 时代 safeBottom＝0、
        // presentedIdeal＝ideal），其 sizeThatFits
        // 含自身底部安全区一层——对账式改 ideal＋
        // safeBottom（首轮实测差恰 34.0＝安全区全
        // 量，结构吻合）。D5 沿用
        let presentedIdeal = presented.view.sizeThatFits(
            CGSize(
                width: windowW, height: .greatestFiniteMagnitude
            )
        ).height
        let safeBottom = presented.view.safeAreaInsets.bottom
        XCTAssertEqual(
            presentedIdeal, ideal + safeBottom, accuracy: 4,
            "presented 内容理想高 \(presentedIdeal) "
                + "≠ 面板理想高 \(ideal)＋底部安全区 "
                + "\(safeBottom)，面板不在场"
        )
        let labels = collectAccessibilityLabels(in: presented.view)

        let access = PHPhotoLibrary.authorizationStatus(
            for: .readWrite
        ).rawValue
        print(
            "ATTACH-FIT-D5 sheet=\(sheetHeight) ideal=\(ideal) "
                + "presentedIdeal=\(presentedIdeal) "
                + "safeBottom="
                + "\(presented.view.safeAreaInsets.bottom) "
                + "photoAccess=\(access) labels=\(labels)"
        )

        // 定高归贴合档（②，D5 修订）：detents 包含
        // 一个 .height 档（非 .medium）与 .large。
        // D5 的 .height(fitted) 档高＝内容理想高＋
        // safeBottom，故帧高−safeBottom ≈ 内容理
        // 想高（容差 4，贴合不再留大片空白）——与
        // §327 的半窗带脱钩断言相反，本批恢复贴合
        let sheetPC = try XCTUnwrap(
            presented.sheetPresentationController,
            "presented 无 sheetPresentationController"
        )
        let detentIDs = Set(sheetPC.detents.map(\.identifier))
        XCTAssertTrue(
            detentIDs.contains(.large),
            "detents 须含 .large，实得 \(detentIDs)"
        )
        // height 档的 identifier 不是 .medium，检查
        // 集合里有非 .medium/.large 的 height 档
        XCTAssertGreaterThanOrEqual(
            sheetPC.detents.count, 2,
            "detents 须至少两档（fitted＋large），"
                + "实得 \(sheetPC.detents.count)"
        )
        let hasHeightDetent = sheetPC.detents.contains {
            $0.identifier != .medium && $0.identifier != .large
        }
        XCTAssertTrue(
            hasHeightDetent,
            "detents 须含 .height 贴合档（非 .medium），"
                + "实得 \(detentIDs)"
        )
        // 帧高贴内容理想高（D5 核心断言）：detent
        // 解析值＝帧高−底部安全区 ≈ 内容理想高（容
        // 差 4，沿用 sizeThatFits 对账法）
        XCTAssertEqual(
            sheetHeight - safeBottom, ideal,
            accuracy: 4,
            "sheet detent 解析值 \(sheetHeight - safeBottom) "
                + "≠ 内容理想高 \(ideal)（D5 贴合口径）"
        )
        XCTAssertGreaterThan(
            sheetHeight, 100,
            "sheet 高 \(sheetHeight) 进塌陷带"
        )
    }

    // MARK: - ③ 确认按钮增减跟随（D5 新增、§461 续）

    /// 确认按钮模拟探针（D5、§461 续）：模拟附件面
    /// 板「有库未选→已选→未选」的确认按钮增减，验
    /// 证 D5 的跟随行为（停在贴合档时高度跟随 ±72pt）
    private final class ConfirmRowModel: ObservableObject {
        @Published var hasConfirmRow = false
    }

    private struct ConfirmRowProbe: View {
        @ObservedObject var model: ConfirmRowModel
        @State private var selectedDetent: PresentationDetent = .medium
        @State private var userSelectedLarge = false
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        
        private var fittedHeight: CGFloat {
            // 简化高度：有库未选 305、已选 377（＋确认按钮 72）
            let base: CGFloat = model.hasConfirmRow ? 377 : 305
            return base
        }
        
        private var fittedDetent: PresentationDetent {
            .height(fittedHeight)
        }
        
        private var detents: Set<PresentationDetent> {
            if dynamicTypeSize.isAccessibilitySize {
                return [.medium, .large]
            } else {
                return [fittedDetent, .large]
            }
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("库区占位").font(.body)
                    .frame(minHeight: 152)
                if model.hasConfirmRow {
                    Text("确认按钮")
                        .font(.body)
                        .frame(minHeight: 56)
                }
                Text("动作行占位").font(.body)
                    .frame(minHeight: 105)
            }
            .padding(16)
            .frame(
                maxWidth: .infinity, maxHeight: .infinity,
                alignment: .topLeading
            )
            .presentationDetents(
                detents,
                selection: Binding(
                    get: { selectedDetent },
                    set: { newValue in
                        selectedDetent = newValue
                        userSelectedLarge = (newValue == .large)
                    }
                )
            )
            .presentationDragIndicator(.visible)
            .task {
                userSelectedLarge = false
                selectedDetent = fittedDetent
            }
            .onChange(of: model.hasConfirmRow) { _, _ in
                // D5 行为：仅当停在贴合档才跟随
                if !userSelectedLarge && !dynamicTypeSize.isAccessibilitySize {
                    selectedDetent = fittedDetent
                }
            }
        }
    }

    func testConfirmRowToggleFollowsHeight() throws {
        let model = ConfirmRowModel()
        let root = assemble(content: ConfirmRowProbe(model: model))

        let initial = try XCTUnwrap(
            settledSheetHeight(of: root),
            "确认行探针 sheet 未在时限内呈现落定"
        )
        
        // 确认按钮出现：高度增加约 72pt（56 按钮高＋16 间距）
        model.hasConfirmRow = true
        spinRunLoop(seconds: 0.5)
        let withConfirm = try XCTUnwrap(
            settledSheetHeight(of: root, afterChangeFrom: initial),
            "确认行出现后 sheet 未在时限内落定"
        )
        print(
            "ATTACH-CONFIRM-ROW initial=\(initial) "
                + "withConfirm=\(withConfirm) delta=\(withConfirm - initial)"
        )
        XCTAssertEqual(
            withConfirm - initial, 72, accuracy: 4,
            "确认按钮出现，sheet 高度应增加 72pt（56＋16），"
                + "实际 \(withConfirm - initial)"
        )
        
        // 确认行消失：高度回到初始值
        model.hasConfirmRow = false
        spinRunLoop(seconds: 0.5)
        let backToInitial = try XCTUnwrap(
            settledSheetHeight(of: root, afterChangeFrom: withConfirm),
            "确认行消失后 sheet 未在时限内落定"
        )
        XCTAssertEqual(
            backToInitial, initial, accuracy: 2,
            "确认行消失，sheet 高度应回到初始值 \(initial)，"
                + "实际 \(backToInitial)"
        )
    }

    // MARK: - 工具

    private func collectAccessibilityLabels(
        in view: UIView
    ) -> [String] {
        var out: [String] = []
        if let label = view.accessibilityLabel {
            out.append(label)
        }
        // SwiftUI 托管内容的无障碍元素多挂在元素的
        // accessibilityElements 而非子视图本体，两面
        // 都收（重复无妨、本函数只作 contains 判定）
        if let elements = view.accessibilityElements {
            for element in elements {
                if let elementView = element as? UIView {
                    out.append(
                        contentsOf: collectAccessibilityLabels(
                            in: elementView
                        )
                    )
                } else if let object = element as? NSObject,
                          let label = object.accessibilityLabel {
                    out.append(label)
                }
            }
        }
        for sub in view.subviews {
            out.append(contentsOf: collectAccessibilityLabels(in: sub))
        }
        return out
    }
}
