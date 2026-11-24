import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §320（文件牌版本折算修复）→§325（B 档后形态）
/// 真实时序装配断言：诊断 file-attach-invisible-
/// diagnosis-20261117 §B5 的断点是时序形的——条
/// 目先以无附件形态物化（发送瞬间：正文已落盘、
/// remoteFilePaths 恒空），上传回填随后才写
/// remoteFilePathsData。本例按此时序造例，不测
/// 静态有附件的行（静态行首帧即带附件、走的是
/// 另一条物化路，测不出断点）：
/// ①种子用户条目（正文＋无附件）整页装配——该
/// 行物化为托管 cell（§325 单渲染路径：全体行
/// 同一种形态）；
/// ②按生产回填原样落盘（ChatView 发送链 §121：
/// remoteFilePathsData＝JSONEncoder().encode(
/// [String])＋save）——条目全字段快照派生的修
/// 订值必变（§325）、同行被原位重配：cell 形态
/// 不变（仍托管）、行高较回填前增长 ≥40（文件
/// 牌组进行内呈现的真实排版高）。文件名文本在
/// 托管子树的观测边界见 ③ 注（§294.1 定版两通
/// 道实证采不到、不再换观测法；牌面视觉在席归
/// 真机验收）。
/// 机制注：§320 时代断点在手折版本哈希漏折文件
/// 数；§325 后判变靠修订值全量比较——快照含
/// remoteFilePathsData 本体，漏折这一错误形态
/// 由构造消除，本例即其装配级回归。
@MainActor
final class FileChipVersionFixAssemblyTests: XCTestCase {

    /// 与整页组装回归同口径的设备窗：402×874、
    /// 安全区覆写 top 59／bottom 34（真机同值）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    /// §184：容器租约——挂载树的容器进进程级持有、
    /// 永不释放，见 SwiftDataTestMount
    private var swiftDataMount = SwiftDataTestMount()
    private var container: ModelContainer!
    private var entryID: UUID!

    /// 与诊断实证同名（用户 2026-11-17 13:12 真机
    /// 所发账单文件）
    private let filePath =
        "/opt/data/attachments/iCost_20261018200435.xlsx"
    private let fileName = "iCost_20261018200435.xlsx"

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        container = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    // MARK: - 装配

    private func assembleSeededPage() throws {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
        // §184：容器进租约——方法返回后仍由租约强
        // 持有，不许只存方法局部
        swiftDataMount.retain(container)
        self.container = container

        // 种子：一条线程＋一条无附件用户条目（发
        // 送瞬间形态——正文已落盘、附件未回填）
        let context = ModelContext(container)
        let thread = ChatThread(title: "主线")
        let entry = ChatEntry(
            role: "user", content: "能不能看到", thread: thread
        )
        context.insert(thread)
        context.insert(entry)
        try context.save()
        entryID = entry.id

        let appState = AppState(
            client: DemoHermesClient(), demoMode: .connected
        )
        // 落点须钉在种子线程：ChatView 冷启 bootstrap
        // 先 ensureMainThread 另建空主线、落点解析默认
        // 回主线——不预选则展示的是那条空线、种子行永
        // 不入列（第一轮 CI 实证：列表 0 行、阶段一超
        // 时）。走生产入口预选（抽屉线程选择，bootstrap
        // 里优先于落点解析消费）
        appState.router.drawerThreadSelection = thread.id
        let host = UIHostingController(
            rootView: ChatView(overviewStore: nil)
                .environment(appState)
                .environment(\.locale, AppLocale.uiLocale)
                .modelContainer(container)
        )
        window = DeviceWindow(
            frame: CGRect(x: 0, y: 0, width: 402, height: 874)
        )
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    // MARK: - 定位助手

    private func findNativeRootController()
        -> ChatRootViewController? {
        var found: ChatRootViewController?
        func walk(_ vc: UIViewController) {
            if let hit = vc as? ChatRootViewController {
                found = hit
            }
            for child in vc.children { walk(child) }
        }
        if let root = window.rootViewController { walk(root) }
        return found
    }

    /// 泵主 runloop 直到条件成立或超时（跨上下文
    /// 落盘的传播与承载落定拍都在 runloop 上推进，
    /// 静态读数等不到）
    private func waitUntil(
        timeout: TimeInterval = 20,
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

    /// 当前可见 cell 中的条目行（种子只有一条条
    /// 目，取可见 item 序最小者——条目行恒在行集
    /// 首位）
    private func entryCell(
        in controller: ChatRootViewController
    ) -> (cell: UICollectionViewCell, indexPath: IndexPath)? {
        let cv = controller.collectionView
        guard let indexPath = cv.indexPathsForVisibleItems
            .sorted(by: { $0.section < $1.section }).first,
              let cell = cv.cellForItem(at: indexPath)
        else { return nil }
        return (cell, indexPath)
    }

    private func frame(
        in controller: ChatRootViewController,
        at indexPath: IndexPath
    ) -> CGRect? {
        controller.collectionView
            .layoutAttributesForItem(at: indexPath)?.frame
    }

    // MARK: - 主例：回填时序换装

    func testSentFileChipAppearsAfterBackfillRedress() throws {
        try assembleSeededPage()

        // ① 回填前：原生面在场、条目行已物化（托管形态）
        var seed: (cell: UICollectionViewCell,
                   indexPath: IndexPath)?
        var phase1Diag = "未见原生根控制器"
        let phase1 = waitUntil {
            guard let controller =
                self.findNativeRootController()
            else { return false }
            self.window.layoutIfNeeded()
            let cv = controller.collectionView
            phase1Diag = "sections="
                + "\(cv.numberOfSections)"
                + " visible="
                + "\(cv.indexPathsForVisibleItems.count)"
            seed = self.entryCell(in: controller)
            return seed != nil
        }
        XCTAssertTrue(
            phase1,
            "回填前条目行须已物化（发送瞬间形态）；"
                + "末次诊断：\(phase1Diag)"
        )
        let unwrappedSeed = try XCTUnwrap(seed)
        XCTAssertEqual(
            unwrappedSeed.cell.reuseIdentifier,
            "ChatNativeHostingCell",
            "§325 单路径：回填前条目行须为托管 cell"
        )
        let controller = try XCTUnwrap(
            findNativeRootController()
        )
        let seedHeight = try XCTUnwrap(
            frame(in: controller, at: unwrappedSeed.indexPath)
        ).height

        // ② 生产回填原样落盘（§121 发送回填同形：
        // 回执路径 JSON 编码写入 remoteFilePaths-
        // Data＋save；落盘上下文＝视图的环境上下文
        // ——生产发送链正是经 ChatView 的 model-
        // Context 回填（markSendState(in: model-
        // Context) 同链），托管下即容器 mainContext；
        // 第二轮 CI 实证：兄弟上下文落盘不刷新视图
        // 经关系持有的条目实例、行永不重配）
        let context = container.mainContext
        let targetID = try XCTUnwrap(entryID)
        let descriptor = FetchDescriptor<ChatEntry>(
            predicate: #Predicate { $0.id == targetID }
        )
        let entry = try XCTUnwrap(
            try context.fetch(descriptor).first
        )
        entry.remoteFilePathsData =
            try JSONEncoder().encode([filePath])
        try context.save()

        // ③ 回填后：修订值变→同行原位重配——形态
        // 不变（仍托管 cell）、行高增长牌高量级。
        // 观测边界（§320 第四~六轮 CI 实证后主线
        // 拍板收口、§325 沿用）：文件名文本在托管
        // 子树两通道均采不到（无障碍通道 labels=0、
        // 视图树通道 texts 只得正文），不再换第三
        // 种观测法；牌面在席的证据链＝修订快照含
        // remoteFilePathsData 本体（字段非空即修
        // 订必变、重配必达）＋托管行画牌为代码直
        // 读条件（ChatView entryRowContent：非空
        // 即 ForEach FileChip）＋真机验收点承接
        let indexPath = unwrappedSeed.indexPath
        var dressedHeight: CGFloat = 0
        var phase2Diag = "cell 未取到"
        let phase2 = waitUntil {
            self.window.layoutIfNeeded()
            guard let cell = controller.collectionView
                .cellForItem(at: indexPath)
            else {
                phase2Diag = "cell 未取到"
                return false
            }
            phase2Diag = "cell=\(type(of: cell))"
                + " reuse=\(cell.reuseIdentifier ?? "nil")"
            if let height = self.frame(
                in: controller, at: indexPath
            )?.height {
                dressedHeight = height
            }
            return dressedHeight > seedHeight + 40
        }
        XCTAssertTrue(
            phase2,
            "回填后该行须原位重配且行高增长牌高量级"
                + "（修订值变的结构证据）；末次诊断："
                + "\(phase2Diag)"
        )
        XCTAssertGreaterThan(
            dressedHeight - seedHeight, 40,
            "重配后行高须较回填前增长牌高量级："
                + "\(seedHeight)→\(dressedHeight)"
        )
    }
}
