import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// 聊天可靠性包（2026-11-13）验收钉测，用户两宗实
/// 报的复现→修复对照：
/// 件一「断网后聊天记录消失」——以全失败客户端
/// （FailingHermesClient，服务器完全不可达）装配
/// 生产 RootView 打开主线/旁聊：落盘存量条目必须
/// 全部在屏（本地优先、永不空白），且打开动作不
/// 许删改任何本地条目；发送失败保留口径的落盘半
/// 边（markPendingSend）单独钉。
/// 件二「助手发图只剩裸路径」——整条裸路径的助手
/// 消息在屏上不许再以路径原文出现，必须走附件形
/// 态（文件名可达、整串路径不成正文）。
@MainActor
final class ChatReliabilityOfflineTests: XCTestCase {

    /// 与组装回归同口径的设备窗（402×874、安全区覆写）
    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!

    override func tearDown() async throws {
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: seconds + 5)
    }

    // MARK: - 装配与播种

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    /// 播种一对线程（主线＋旁聊）与各自条目，createdAt
    /// 逐条错开保序；返回两线程（id 跨上下文以 uuid 对齐）
    private func seedThreads(
        in container: ModelContainer,
        mainEntries: [(role: String, content: String)],
        sideEntries: [(role: String, content: String)]
    ) throws -> (main: ChatThread, side: ChatThread) {
        let context = ModelContext(container)
        let main = ChatThread(title: "主线")
        let side = ChatThread(title: "旁聊")
        context.insert(main)
        context.insert(side)
        let base = Date(timeIntervalSince1970: 1_763_000_000)
        for (index, item) in mainEntries.enumerated() {
            let entry = ChatEntry(
                role: item.role, content: item.content, thread: main
            )
            entry.createdAt = base.addingTimeInterval(Double(index))
            context.insert(entry)
        }
        for (index, item) in sideEntries.enumerated() {
            let entry = ChatEntry(
                role: item.role, content: item.content, thread: side
            )
            entry.createdAt = base.addingTimeInterval(Double(index))
            context.insert(entry)
        }
        try context.save()
        return (main, side)
    }

    /// 以全失败客户端装配生产整页并等渲染落稳
    private func mountOffline(
        container: ModelContainer, appState: AppState
    ) {
        let host = UIHostingController(
            rootView: RootView()
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
        spinRunLoop(seconds: 3.0)
        window.layoutIfNeeded()
    }

    /// 在屏文本全集：无障碍标签/值＋真实 UILabel/
    /// UITextView 的文本（消息正文经 SelectableUI-
    /// TextView 落在真实 UITextView 上）
    private func onScreenTexts() -> [String] {
        var texts: [String] = []
        func collect(from view: UIView) {
            if let label = view.accessibilityLabel {
                texts.append(label)
            }
            if let value = view.accessibilityValue {
                texts.append(value)
            }
            if let label = view as? UILabel, let text = label.text {
                texts.append(text)
            }
            if let textView = view as? UITextView {
                texts.append(textView.text ?? "")
            }
            if let elements = view.accessibilityElements {
                for element in elements {
                    if let elementView = element as? UIView {
                        collect(from: elementView)
                    } else if let el = element
                        as? UIAccessibilityElement,
                        let label = el.accessibilityLabel {
                        texts.append(label)
                    }
                }
            }
            for subview in view.subviews {
                collect(from: subview)
            }
        }
        if let window {
            collect(from: window)
        }
        return texts
    }

    /// 断网打开后回读容器：两线程与全部条目必须原样
    /// （打开/落点/续跑/链接预热一整套动作在全失败下
    /// 不许删改任何存量）
    private func assertStoreIntact(
        container: ModelContainer,
        mainCount: Int, sideCount: Int,
        contents: [String],
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        XCTAssertEqual(threads.count, 2, file: file, line: line)
        let entries = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        XCTAssertEqual(
            entries.count, mainCount + sideCount,
            file: file, line: line
        )
        for content in contents {
            XCTAssertTrue(
                entries.contains { $0.content == content },
                "条目丢失：\(content)",
                file: file, line: line
            )
        }
    }

    // MARK: - 件一：断网打开主线/旁聊，存量全在屏

    func testOfflineOpenMainThreadShowsLocalRecords() throws {
        let container = try makeContainer()
        let seeded = try seedThreads(
            in: container,
            mainEntries: [
                ("user", "离线主线标记问句甲"),
                ("assistant", "离线主线标记答复乙"),
                ("user", "离线主线标记问句丙"),
            ],
            sideEntries: [("user", "离线旁聊标记问句丁")]
        )
        let appState = AppState(
            client: FailingHermesClient(), demoMode: .connected
        )
        appState.sideChats.designateMainThread(seeded.main.id)
        appState.sideChats.setLastThreadID(seeded.main.id)
        mountOffline(container: container, appState: appState)

        let texts = onScreenTexts()
        for marker in ["离线主线标记问句甲", "离线主线标记答复乙", "离线主线标记问句丙"] {
            XCTAssertTrue(
                texts.contains { $0.contains(marker) },
                "断网打开主线应见存量条目：\(marker)"
            )
        }
        try assertStoreIntact(
            container: container, mainCount: 3, sideCount: 1,
            contents: [
                "离线主线标记问句甲", "离线主线标记答复乙",
                "离线主线标记问句丙", "离线旁聊标记问句丁",
            ]
        )
    }

    func testOfflineOpenSideThreadShowsLocalRecords() throws {
        let container = try makeContainer()
        let seeded = try seedThreads(
            in: container,
            mainEntries: [("user", "离线主线标记问句甲")],
            sideEntries: [
                ("user", "离线旁聊标记问句丁"),
                ("assistant", "离线旁聊标记答复戊"),
            ]
        )
        let appState = AppState(
            client: FailingHermesClient(), demoMode: .connected
        )
        appState.sideChats.designateMainThread(seeded.main.id)
        appState.sideChats.setLastThreadID(seeded.side.id)
        mountOffline(container: container, appState: appState)

        let texts = onScreenTexts()
        for marker in ["离线旁聊标记问句丁", "离线旁聊标记答复戊"] {
            XCTAssertTrue(
                texts.contains { $0.contains(marker) },
                "断网打开旁聊应见存量条目：\(marker)"
            )
        }
        try assertStoreIntact(
            container: container, mainCount: 1, sideCount: 2,
            contents: [
                "离线主线标记问句甲", "离线旁聊标记问句丁",
                "离线旁聊标记答复戊",
            ]
        )
    }

    // MARK: - 件一：发送失败保留口径（落盘半边）

    /// markPendingSend：条目不删、内容原样、待发标
    /// 记落盘可回读（send() 三个失败分支共用此口；
    /// 分支接线由代码审与真机验收兜底，本测钉落盘
    /// 语义本身不回潮成删除）
    func testMarkPendingSendRetainsEntryOnDisk() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = ChatThread(title: "旁聊")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "断网时写下的消息", thread: thread
        )
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.deliveryState)
        XCTAssertFalse(entry.isPendingSend)

        entry.markPendingSend(in: context)

        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<ChatEntry>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "断网时写下的消息")
        XCTAssertEqual(fetched.first?.deliveryState, "pending")
        XCTAssertTrue(fetched.first?.isPendingSend == true)
    }

    // MARK: - 件二：整条裸路径不再当正文

    /// 实案复刻：助手消息全文＝头像图裸路径。断网
    /// （下载必失败）下附件形态的诚实失败态可以出
    /// 现，但整串路径不许以正文形态在屏，文件名须
    /// 经附件口径可达
    func testBareImagePathMessageNotRenderedAsRawText() throws {
        let container = try makeContainer()
        let seeded = try seedThreads(
            in: container,
            mainEntries: [
                ("user", "发我看看？"),
                ("assistant", "/opt/data/cache/scratch/avatar_small.png"),
            ],
            sideEntries: [("user", "占位旁聊条目")]
        )
        let appState = AppState(
            client: FailingHermesClient(), demoMode: .connected
        )
        appState.sideChats.designateMainThread(seeded.main.id)
        appState.sideChats.setLastThreadID(seeded.main.id)
        mountOffline(container: container, appState: appState)

        let texts = onScreenTexts()
        XCTAssertFalse(
            texts.contains {
                $0.contains("/opt/data/cache/scratch/avatar_small.png")
            },
            "整条裸路径不许原样当正文在屏"
        )
        XCTAssertTrue(
            texts.contains { $0.contains("avatar_small.png") },
            "附件形态应以文件名可达（图片标签/失败卡）"
        )
    }

    /// 文件形态同理：整条裸路径（非图片）出文件卡、
    /// 不出路径正文
    func testBareFilePathMessageNotRenderedAsRawText() throws {
        let container = try makeContainer()
        let seeded = try seedThreads(
            in: container,
            mainEntries: [
                ("user", "清单发我"),
                ("assistant", "/opt/data/reports/婚礼清单.pdf"),
            ],
            sideEntries: [("user", "占位旁聊条目")]
        )
        let appState = AppState(
            client: FailingHermesClient(), demoMode: .connected
        )
        appState.sideChats.designateMainThread(seeded.main.id)
        appState.sideChats.setLastThreadID(seeded.main.id)
        mountOffline(container: container, appState: appState)

        let texts = onScreenTexts()
        XCTAssertFalse(
            texts.contains {
                $0.contains("/opt/data/reports/婚礼清单.pdf")
            },
            "整条裸路径不许原样当正文在屏"
        )
        XCTAssertTrue(
            texts.contains { $0.contains("婚礼清单.pdf") },
            "文件卡应以文件名可达"
        )
    }
}
