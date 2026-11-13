import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import OneDayApp

/// 键盘协同整包（2026-11-13）· 落码后验收门。
/// 观测口径全部取自诊断轮实测教训（run 43447354946）：
/// ①点空白识别器在位且仲裁参数对（cancelsTouchesInView
/// ＝false、delegate 为安装器视图）；
/// ②margin 两态值：静息 rawB＝197（账本 83+106+8）、
/// 键盘态 rawB＝449（键盘 335+舱 106+8）——快照公式与
/// 旧回报链在同装配下逐 pt 同值即过（容差 ±3 吸收舱高
/// 内容差）；adjusted 的平台键盘调整（实测 +79）不在
/// 本账内、只记 raw；
/// ③顶簇静止：聚焦→收起全周期 pocketY 最大偏差 ≤2；
/// ④落定无尾巴：收键盘后 +0.6s 与 +2.2s 两采样 pocket/
/// card 逐项一致（≤1）且 rawB 回到静息值 ±3。
/// 落点 gap 的绝对值不在本门内：诊断轮实证模拟器装配
/// 的 LazyVStack 估算膨胀（首贴 Δ637）使 UIKit 层 gap
/// 读数不可作生产落点判据；落点质量由 Core 结算状态
/// 机单测＋生产贴底链（锚点 scrollTo）承载，真机为最
/// 终判据（与 §194 同纪律：模拟器绿不等于真机绿）。
/// 装配纪律：本文件只装配一次 RootView、只播种一次
/// （§184 配方：同进程多次整页装配＋异容器 save 必杀
/// 是测试宿主病，压暴露面）。
@MainActor
final class KeyboardFlowAcceptanceTests: XCTestCase {
    private var window: UIWindow?
    private var container: ModelContainer?

    override func tearDown() {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        container = nil
    }

    private func pump(until condition: () -> Bool, seconds: Double = 20) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func pump(seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func findViews<T: UIView>(
        _ type: T.Type, in view: UIView
    ) -> [T] {
        var out: [T] = []
        if let hit = view as? T { out.append(hit) }
        for sub in view.subviews {
            out.append(contentsOf: findViews(type, in: sub))
        }
        return out
    }

    private func chatScrollView() -> UIScrollView? {
        guard let win = window else { return nil }
        return findViews(UIScrollView.self, in: win)
            .filter {
                String(describing: type(of: $0))
                    .contains("HostingScrollView")
                    && $0.bounds.width > 400
            }
            .max(by: { $0.bounds.height < $1.bounds.height })
    }

    private func composerTextView() -> UITextView? {
        guard let win = window else { return nil }
        return findViews(UITextView.self, in: win)
            .filter { $0.frame(in: nil).width > 200 }
            .max(by: {
                $0.frame(in: nil).minY < $1.frame(in: nil).minY
            })
    }

    private func pocketFrame() -> CGRect? {
        guard let win = window else { return nil }
        return findViews(UIView.self, in: win)
            .filter {
                String(describing: type(of: $0)).contains("TopBarGuideHost")
            }
            .first?.frame(in: nil)
    }

    private func cardTop() -> CGFloat? {
        guard let win = window else { return nil }
        return findViews(UIView.self, in: win)
            .filter {
                String(describing: type(of: $0))
                    .contains("UIPlatformGlassInteractionView")
                    && $0.frame(in: nil).width > 300
            }
            .map { $0.frame(in: nil).minY }
            .min()
    }

    func testKeyboardFlowAcceptance() throws {
        let schema = Schema(versionedSchema: OneDaySchemaV5.self)
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: schema, migrationPlan: OneDayMigrationPlan.self,
            configurations: config
        )
        self.container = container
        let context = ModelContext(container)
        let session = WorkSession(
            id: "kbaccept-main", title: "验收主线",
            source: .main, status: .active
        )
        context.insert(session)
        let paragraph = (0..<8).map { i in
            "第\(i + 1)段：键盘验收的长段落文本，"
                + "用来撑起真实的气泡高度与行高。"
        }.joined(separator: " ")
        for index in 0..<160 {
            context.insert(WorkEntry(
                id: "kbaccept-\(index)",
                type: index % 2 == 0 ? .user : .assistant,
                content: index % 3 == 0
                    ? "短消息 \(index)"
                    : "消息 \(index)。" + paragraph,
                source: .local, status: .done
            ))
        }
        try context.save()

        let appState = OneDayAppState()
        appState.workSessionStore = WorkSessionStore(
            modelContext: context
        )
        appState.sideChats.setLastThreadID("kbaccept-main")
        let host = UIHostingController(
            rootView: RootView()
                .environment(appState)
                .environment(ConnectionStore())
                .environment(VisualLabSettings())
                .modelContainer(container)
        )
        let window = UIWindow(frame: CGRect(
            x: 0, y: 0, width: 402, height: 874
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        pump(seconds: 5)

        guard let scroll = chatScrollView() else {
            XCTFail("验收装配失效：找不到聊天滚动视图")
            return
        }

        // ① 识别器在位（A5 条）
        let recognizer = scroll.gestureRecognizers?.first {
            $0.name == "OneDayBlankTapDismiss"
        }
        XCTAssertNotNil(
            recognizer,
            "点空白退键盘识别器未安装到聊天滚动视图"
        )
        if let recognizer {
            XCTAssertFalse(
                recognizer.cancelsTouchesInView,
                "识别器不许吞触摸（cancelsTouchesInView 须 false）"
            )
            XCTAssertTrue(
                recognizer.delegate is TapDismissInstallerView,
                "识别器 delegate 须为安装器视图（仲裁在 delegate）"
            )
        }

        // ② 静息 margin（raw 口径）
        let restRawB = scroll.contentInset.bottom
        let restPocket = pocketFrame()?.minY ?? -1
        let restCard = cardTop() ?? -1
        print(String(format:
            "KBACCEPT rest rawB=%.0f pocket=%.0f card=%.0f",
            restRawB, restPocket, restCard))
        XCTAssertEqual(
            restRawB, 197, accuracy: 3,
            "静息底 margin 与账本值不符（83+106+8）"
        )

        // 键盘周期：聚焦→采样→收起→两拍采样
        guard let composer = composerTextView(),
              composer.becomeFirstResponder() else {
            XCTFail("验收装配失效：输入舱无法聚焦")
            return
        }
        var pocketSamples: [CGFloat] = [restPocket]
        pump(seconds: 0.8)
        pocketSamples.append(pocketFrame()?.minY ?? -1)
        let kbRawB = scroll.contentInset.bottom
        print(String(format:
            "KBACCEPT kb rawB=%.0f pocket=%.0f",
            kbRawB, pocketSamples.last ?? -1))
        XCTAssertEqual(
            kbRawB, 449, accuracy: 3,
            "键盘态底 margin 与快照公式不符（335+106+8）"
        )
        XCTAssertEqual(
            pocketSamples.last ?? -1, restPocket, accuracy: 2,
            "键盘升起顶簇位移"
        )
        _ = composer.resignFirstResponder()
        pump(seconds: 0.6)
        let settledRawB = scroll.contentInset.bottom
        let settledPocket = pocketFrame()?.minY ?? -1
        let settledCard = cardTop() ?? -1
        pump(seconds: 1.6)
        let latePocket = pocketFrame()?.minY ?? -1
        let lateCard = cardTop() ?? -1
        print(String(format:
            "KBACCEPT settled rawB=%.0f pocket=%.0f/%.0f card=%.0f/%.0f",
            settledRawB, settledPocket, latePocket,
            settledCard, lateCard))

        // ③④ 收起落定：无尾巴＋顶簇全周期静止＋margin 归位
        XCTAssertEqual(
            settledPocket, latePocket, accuracy: 1,
            "收键盘后顶簇仍在爬行（落定尾巴）"
        )
        XCTAssertEqual(
            settledCard, lateCard, accuracy: 1,
            "收键盘后输入舱仍在爬行（落定尾巴）"
        )
        XCTAssertEqual(
            settledPocket, restPocket, accuracy: 2,
            "顶簇收键盘全程位移超限"
        )
        XCTAssertEqual(
            settledRawB, restRawB, accuracy: 3,
            "收键盘后底 margin 未回到静息值"
        )
    }
}
