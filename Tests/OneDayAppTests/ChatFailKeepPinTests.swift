import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §414（修复包一·失败不消失）端到端钉测：三条与
/// 红感叹号定版脱节的路——
/// 路一（落盘前弹回→落位待发）：send() 落位分支
/// 本体在发送钮后（见下「可达面」注），钉其消费
/// 者半边两段：账本在位时发件箱不许抢发待发条目
/// （账本门）、账本落定后 drain 按落盘序原位派发
/// （派发后同 id 同序位、链接段落败转失败态）；
/// 路二（重发复制删原条→原位重发）：挂载 drain
/// 自动派发即走 resendFailedEntry 生产同路——派
/// 发落账（自动尝试记账）＋原条目同 id 同序位留
/// 存、总数与 id 集不变（基线复制删原条口径下本
/// 钉必红）；半截候选谓词的「下一轮界」单独模型
/// 级钉；
/// 路三（编辑未发送回收删条→原位写回）：写回原
/// 语 applyUnsentEdit 模型级钉——同 id/同时刻/
/// 同序位、内容与图片全集与引用换新、发送状态
/// 一字不动。
/// 增补（断网规格）：占位行文案相全集纯函数钉、
/// 未确认谓词钉（队列四态/失败/投递/无状态＋高
/// 度快照同源派生）。
///
/// 可达面实证（2026-11-23 三轮诊断）：本仓托管式
/// 单测环境不供出 SwiftUI 无障碍元素——accessi-
/// bilityElements 属性口与 accessibilityElement-
/// Count/at: 协议口遍历均为零元素零标签，消息正
/// 文仅经真实 UITextView 可见；发送钮与气泡旁发
/// 送状态标记（SwiftUI Button）在此环境不可达，
/// accessibilityActivate 点按驱动已被证伪。故端
/// 到端钉改走发件箱 drain 的真实派发面（挂载
/// .task／网络恢复 epoch 均为生产同路触发），断
/// 言落存储回读与自动尝试记账；send() 落位分支
/// 本体、时钟/红叹号标记在屏呈现列真机门（见
/// DESIGN §414）。
/// 装配：CountingCatalogClient 让 connectDirect
/// 在测试内落位 config/apiKey（drain 守卫所需），
/// 其余口恒抛 unreachable——重发必在链接段落败，
/// 落点与 ChatReliabilityOfflineTests 同口径。
@MainActor
final class ChatFailKeepPinTests: XCTestCase {

    private final class DeviceWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets {
            UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        }
    }

    private var window: DeviceWindow!
    /// §184：容器租约——见 SwiftDataTestMount。
    private var swiftDataMount = SwiftDataTestMount()
    /// 账本清理名单：滞留账本经 AppState 落 User-
    /// Defaults，测试毕必须摘除防污染后续套件
    private var ledgerThreadIDs: [UUID] = []
    private var ledgerStore: RunLedgerStore?
    /// 已连接装配的善后：disconnect 清 Keychain 与
    /// config，防本套件凭据污染后续套件
    private var connectedState: AppState?

    override func tearDown() async throws {
        for id in ledgerThreadIDs {
            ledgerStore?.remove(threadID: id)
        }
        ledgerThreadIDs = []
        ledgerStore = nil
        connectedState?.disconnect()
        connectedState = nil
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        await swiftDataMount.release()
        try await super.tearDown()
    }

    private func spinRunLoop(seconds: TimeInterval) async {
        // §414 收尾定因（两段）：等待必须真挂起——同步
        // wait(for:) 冻主线程致 fulfill 不达（一段）；改
        // RunLoop 手工泵送后计时器可达，但同步自旋仍占住
        // MainActor 执行器，drain 的 Task 在整个轮询期被
        // 饿死（探针实证：守卫全过、decision=autoNow 的
        // 打印落在测试收尾之后才出现）。Task.sleep 挂起
        // 本方法、让出执行器，被测 App 的任务才有拍可走。
        try? await Task.sleep(
            nanoseconds: UInt64(seconds * 1_000_000_000)
        )
    }

    /// 轮询等条件成立（每 0.25s 让一拍主循环）
    private func pollUntil(
        seconds: TimeInterval, _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await spinRunLoop(seconds: 0.25)
        }
        return condition()
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

    /// 播种单线程条目（createdAt 逐条错开保序）
    @discardableResult
    private func seedThread(
        in container: ModelContainer,
        entries: [(role: String, content: String)]
    ) throws -> ChatThread {
        let context = ModelContext(container)
        let thread = ChatThread(title: "钉测线程")
        context.insert(thread)
        let base = Date(timeIntervalSince1970: 1_763_000_000)
        for (index, item) in entries.enumerated() {
            let entry = ChatEntry(
                role: item.role, content: item.content,
                thread: thread
            )
            entry.createdAt = base.addingTimeInterval(
                Double(index) * 10
            )
            context.insert(entry)
        }
        try context.save()
        return thread
    }

    private func mountRoot(
        container: ModelContainer, appState: AppState
    ) async {
        swiftDataMount.retain(container)
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
        await spinRunLoop(seconds: 4.0)
        window.layoutIfNeeded()
        await spinRunLoop(seconds: 0.8)
        window.layoutIfNeeded()
    }

    /// 已连接装配：演示态＋connectDirect 落位
    /// config——drainOutboxIfNeeded 的守卫（!isDemo、
    /// config/apiKey 非空）由此全过。演示态下 apiKey
    /// 返回假值 "demo-api-key"、不读钥匙串（测试进程
    /// 钥匙串读回为 nil），与 SmokeGateMigrationTests
    /// 同口径
    private func makeConnectedAppState(
        mainThreadID: UUID
    ) async throws -> AppState {
        let sharedOutboxRetry = OutboxRetryStore(persisted: true)
        let sharedSessionLedger = SessionLedger(persisted: true)
        let sharedRunLedger = RunLedgerStore(persisted: true)

        let appState = AppState(
            client: CountingCatalogClient(
                recorder: CatalogCallRecorder()
            ),
            demoMode: .connected,
            outboxRetryStorage: sharedOutboxRetry,
            sessionLedgerStorage: sharedSessionLedger,
            runLedgerStorage: sharedRunLedger
        )
        appState.sessionLedger.designateMainThread(mainThreadID)
        appState.sideChats.setLastThreadID(mainThreadID)
        ledgerStore = appState.runLedger
        connectedState = appState
        try await appState.connectDirect(
            config: try XCTUnwrap(
                ServerConfig(rawInput: "https://failkeep.test")
            ),
            apiKey: "failkeep-test-key"
        )

        XCTAssertNotNil(
            appState.apiKey,
            "演示态 apiKey 应返回假值 demo-api-key"
        )
        return appState
    }

    private func readEntries(
        in container: ModelContainer, threadID: UUID
    ) throws -> [ChatEntry] {
        let context = ModelContext(container)
        let threads = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        guard let thread = threads.first(
            where: { $0.id == threadID }
        ) else { return [] }
        return thread.sortedEntries
    }

    /// 播种三条：已落定一问一答＋一条待发（路一
    /// 两钉共用场景），返回待发条目 id
    private func seedPendingScene(
        in container: ModelContainer
    ) throws -> (thread: ChatThread, pendingID: UUID) {
        let thread = try seedThread(in: container, entries: [
            ("user", "钉测一已落定问句"),
            ("assistant", "钉测一已落定答复"),
            ("user", "钉测一滞留期落位问句"),
        ])
        let context = ModelContext(container)
        let seeded = try context.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let pending = try XCTUnwrap(
            seeded.first { $0.content == "钉测一滞留期落位问句" }
        )
        pending.markPendingSend(in: context)
        try context.save()
        return (thread, pending.id)
    }

    // MARK: - 路一·账本门：账本在位时待发不被抢发

    /// 上一轮账本未落定（runID 未回补、锚在已落定
    /// 首问——提交后未落定的合法形态）：对账以同
    /// key 重演循环（600s 截止），账本恒在位；此间
    /// drain 不许动已落位的待发条目——无自动尝试
    /// 记账、待发身份与序位一字不动
    /// §451 注记：提交已与账本解耦，「账本门」口
    /// 径作废（新条目照常提交、服务端 FIFO 排
    /// 班，见 ChatQueueSendPinTests 钉二改写）；
    /// 本钉两断言在新机制下仅剩存储面意义（首投
    /// 不记自动尝试＋未受理失败保待发标记），不
    /// 再证明「未被派发」——派发与否以钉二为准
    func testPendingEntryHeldWhileLedgerStale() async throws {
        let container = try makeContainer()
        let (thread, pendingID) = try seedPendingScene(
            in: container
        )
        let appState = try await makeConnectedAppState(
            mainThreadID: thread.id
        )
        let firstID = try XCTUnwrap(
            try readEntries(in: container, threadID: thread.id)
                .first?.id
        )
        appState.runLedger.upsert(RunLedgerEntry(
            threadID: thread.id.uuidString,
            sessionID: "oneday-stale-session",
            runID: nil,
            idempotencyKey: "stale-idempotency-key",
            userEntryID: firstID.uuidString,
            submittedAt: Date()
        ))
        ledgerThreadIDs = [thread.id]
        await mountRoot(container: container, appState: appState)
        await spinRunLoop(seconds: 2.5)

        // 存储面改判（0.51.0 收尾轮）：首投失败经失败落点写
        // kind-only 记录系发送失败机制包语义 3 应然（失败落
        // 点必写成因进重试账；成因分类归 SendFailureTests
        // 管辖，本钉不钉 kind 值）；记录对象存在不作断言，
        // 只钉残余口径——首投不记自动尝试。判读见
        // release-0510-stale-ledger-triage-20261125.md。
        let staleRecord = appState.outboxRetry.record(for: pendingID)
        XCTAssertEqual(
            staleRecord?.attempts, 0,
            "账本滞留期首投被记了自动尝试次数"
        )
        XCTAssertNil(
            staleRecord?.lastAttemptAt,
            "账本滞留期首投被记了自动尝试时刻"
        )
        let entries = try readEntries(
            in: container, threadID: thread.id
        )
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[2].id, pendingID)
        XCTAssertTrue(
            entries[2].isPendingSend,
            "账本滞留期待发条目身份被改动"
        )
    }

    // MARK: - 路一·派发：账本落定后按序原位真发

    /// 无账本（上一轮已落定）：挂载 drain 即派发
    /// 待发条目——自动尝试落账、真跑到链接段落败
    /// 后原位转失败态（同 id 同序位、总数不变）。
    /// send() 在账本落定后插入的 drain 钩子与本钉
    /// 走同一 drainOutboxIfNeeded 入口
    func testPendingEntryDispatchedInPlaceOnceLedgerSettles()
        async throws
    {
        let container = try makeContainer()
        let (thread, pendingID) = try seedPendingScene(
            in: container
        )
        let appState = try await makeConnectedAppState(
            mainThreadID: thread.id
        )
        await mountRoot(container: container, appState: appState)

        // §451 记账口径：提交泵首投不记自动尝试
        // （OutboxAutoRetryPolicy 本义「首发不算
        // 自动重试」，§419 drain 经重发口记账的旧
        // 探针自此失效）——派发探针改看失败落点
        // 本身：派发真跑到未受理失败、原位落失败态
        let landedFailed = await pollUntil(seconds: 15) {
            (try? readEntries(
                in: container, threadID: thread.id
            ))?.first { $0.id == pendingID }?.sendFailed
                == true
        }
        XCTAssertTrue(
            landedFailed,
            "账本落定后发件箱未派发待发条目（派发未真跑到失败落点）"
        )
        let entries = try readEntries(
            in: container, threadID: thread.id
        )
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[2].id, pendingID)
    }

    // MARK: - 路二：中段失败条目原位重发（drain 派发）

    /// 中段失败条目由挂载 drain 自动派发重发（与
    /// 点按红感叹号同走 resendFailedEntry）：派发
    /// 落账、再失败后原条目同 id 同序位留存、总数
    /// 与 id 集不变。基线「删原条＋复制追加末尾」
    /// 口径下 id 集与序位断言必红
    func testFailedEntryResendDispatchedInPlace() async throws {
        let container = try makeContainer()
        let thread = try seedThread(in: container, entries: [
            ("user", "钉测二首问"),
            ("assistant", "钉测二首答"),
            ("user", "钉测二中段失败问句"),
            ("user", "钉测二后续问句"),
            ("assistant", "钉测二后续答复"),
        ])
        // 中段条目落失败态（与真实失败落盘同口径）
        let seedContext = ModelContext(container)
        let seeded = try seedContext.fetch(
            FetchDescriptor<ChatEntry>()
        )
        let failedEntry = try XCTUnwrap(
            seeded.first { $0.content == "钉测二中段失败问句" }
        )
        failedEntry.markSendState(.failed, in: seedContext)
        let failedID = failedEntry.id
        try seedContext.save()
        let seededIDs = Set(seeded.map(\.id))

        let appState = try await makeConnectedAppState(
            mainThreadID: thread.id
        )
        await mountRoot(container: container, appState: appState)

        let attempted = await pollUntil(seconds: 10) {
            (appState.outboxRetry.record(for: failedID)?
                .attempts ?? 0) >= 1
        }
        XCTAssertTrue(
            attempted, "发件箱未派发中段失败条目重发"
        )
        let landedFailed = await pollUntil(seconds: 10) {
            (try? readEntries(
                in: container, threadID: thread.id
            ))?.first { $0.id == failedID }?.sendFailed
                == true
        }
        XCTAssertTrue(
            landedFailed,
            "重发再失败后失败态未回归原条目"
        )
        // 原位：同 id、同序位、总数与 id 集不变
        let entries = try readEntries(
            in: container, threadID: thread.id
        )
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(
            Set(entries.map(\.id)), seededIDs,
            "重发删了原条目或添了复制条（id 集已变）"
        )
        XCTAssertEqual(
            entries[2].id, failedID,
            "原失败条目被删/被复制条顶替（身份或位置已变）"
        )
        XCTAssertEqual(entries[2].content, "钉测二中段失败问句")
    }

    // MARK: - 路二谓词钉：半截候选的下一轮界

    func testTurnPartialCandidatesBoundedByNextTurn() throws {
        let container = try makeContainer()
        let thread = try seedThread(in: container, entries: [
            ("user", "谓词钉首问"),
            ("assistant", "谓词钉首答"),
            ("user", "谓词钉中段问"),
            ("assistant", "谓词钉中段半截"),
            ("user", "谓词钉后续问"),
            ("assistant", "谓词钉后续答"),
        ])
        let context = ModelContext(container)
        let fetched = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let fetchedThread = try XCTUnwrap(fetched.first)
        let sorted = fetchedThread.sortedEntries
        // 中段轮：候选只许本轮半截，其后已落定轮次
        // （后续问/后续答）不许入选
        let mid = ChatView.turnPartialCandidates(
            in: fetchedThread, userEntry: sorted[2]
        )
        XCTAssertEqual(
            mid.map(\.content), ["谓词钉中段半截"]
        )
        // 首轮：界为中段问——只含首答
        let first = ChatView.turnPartialCandidates(
            in: fetchedThread, userEntry: sorted[0]
        )
        XCTAssertEqual(first.map(\.content), ["谓词钉首答"])
        // 末轮：无下一轮界——含其后全部（与旧口径同）
        let last = ChatView.turnPartialCandidates(
            in: fetchedThread, userEntry: sorted[4]
        )
        XCTAssertEqual(last.map(\.content), ["谓词钉后续答"])
        // 待发豁免：末尾再挂一条待发用户条目——不
        // 构成轮次边界、自身不入选，末轮候选不变
        let pending = ChatEntry(
            role: "user", content: "谓词钉待发问",
            thread: fetchedThread
        )
        pending.createdAt = sorted[5].createdAt
            .addingTimeInterval(10)
        context.insert(pending)
        pending.markPendingSend(in: context)
        try context.save()
        let lastAfterPending = ChatView.turnPartialCandidates(
            in: fetchedThread, userEntry: sorted[4]
        )
        XCTAssertEqual(
            lastAfterPending.map(\.content), ["谓词钉后续答"]
        )
        _ = thread
    }

    // MARK: - 路三：未发送编辑原位写回

    func testApplyUnsentEditRewritesContentInPlace() throws {
        let container = try makeContainer()
        let thread = try seedThread(in: container, entries: [
            ("user", "路三钉前置问句"),
            ("user", "路三钉旧正文"),
            ("assistant", "路三钉后续答复"),
        ])
        let context = ModelContext(container)
        let fetched = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let fetchedThread = try XCTUnwrap(fetched.first)
        let target = fetchedThread.sortedEntries[1]
        let targetID = target.id
        let targetCreatedAt = target.createdAt
        // 旧形态：带图带引用且已失败
        target.imageData = Data([0x01])
        target.imageDatasData = try JSONEncoder().encode(
            [Data([0x01])]
        )
        target.quoteRole = "user"
        target.quoteContent = "路三钉旧引用"
        target.markSendState(.failed, in: context)
        try context.save()

        target.applyUnsentEdit(
            content: "路三钉新正文",
            imageDatas: [Data([0x02]), Data([0x03])],
            quote: nil,
            sourceQuote: .file(FileQuote(
                name: "路三钉文件.pdf", path: "/tmp/failkeep-pin"
            )),
            in: context
        )

        let after = fetchedThread.sortedEntries
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(after[1].id, targetID)
        XCTAssertEqual(after[1].createdAt, targetCreatedAt)
        XCTAssertEqual(after[1].content, "路三钉新正文")
        XCTAssertEqual(
            after[1].allImageDatas, [Data([0x02]), Data([0x03])]
        )
        XCTAssertNil(after[1].quote)
        XCTAssertEqual(
            after[1].sourceQuote,
            .file(FileQuote(
                name: "路三钉文件.pdf", path: "/tmp/failkeep-pin"
            ))
        )
        // 发送状态一字不动：仍失败态、待重发链自理
        XCTAssertTrue(after[1].sendFailed)
        XCTAssertEqual(after[1].sendStateRaw, "failed")
        _ = thread
    }

    // MARK: - 增补钉（断网规格）：文案相全集

    /// 规格 §六.8：占位行文案五相逐相断言＋铁则
    /// ——「正在生成…」仅在相位 == .generating 可达
    func testPlaceholderStatusTextPhases() {
        func text(
            phase: RunTurnPhase, runID: Bool,
            tail: ChatSendState? = nil,
            uploading: Bool = false,
            fraction: Double? = nil,
            reasoning: Bool = false,
            tools: Bool = false
        ) -> String {
            ChatView.placeholderStatusText(
                phase: phase, runIDEstablished: runID,
                tailSendState: tail, isUploading: uploading,
                uploadFraction: fraction,
                hasReasoning: reasoning, hasToolCards: tools
            )
        }
        // 上传相（带/不带百分比）
        XCTAssertEqual(
            text(phase: .submitting, runID: false,
                 uploading: true, fraction: 0.5),
            "正在上传文件 50%…"
        )
        XCTAssertEqual(
            text(phase: .submitting, runID: false,
                 uploading: true),
            "正在上传文件…"
        )
        // 未受理段：提交相恒等待发送（run 未确立）
        XCTAssertEqual(
            text(phase: .submitting, runID: false),
            "等待发送…"
        )
        XCTAssertEqual(
            text(phase: .submitting, runID: false,
                 tail: .sending),
            "等待发送…"
        )
        // 结果未知/对账相：从未受理→等待发送；已受
        // 理→正在确认结果
        XCTAssertEqual(
            text(phase: .unknown, runID: false),
            "等待发送…"
        )
        XCTAssertEqual(
            text(phase: .reconciling, runID: false),
            "等待发送…"
        )
        XCTAssertEqual(
            text(phase: .unknown, runID: true),
            "正在确认结果…"
        )
        XCTAssertEqual(
            text(phase: .reconciling, runID: true),
            "正在确认结果…"
        )
        // 生成相三文案（submitAccepted 之后才可达）
        XCTAssertEqual(
            text(phase: .generating(stopping: false),
                 runID: true, reasoning: true),
            "正在思考…"
        )
        XCTAssertEqual(
            text(phase: .generating(stopping: false),
                 runID: true, tools: true),
            "正在调用工具…"
        )
        XCTAssertEqual(
            text(phase: .generating(stopping: false),
                 runID: true),
            "正在生成…"
        )
        // 铁则扫全相：非生成相任何输入组合不许产
        // 「正在生成…」
        let phases: [RunTurnPhase] = [
            .submitting, .unknown, .reconciling,
            .finished, .failed,
        ]
        for phase in phases {
            for runID in [false, true] {
                let tails: [ChatSendState?] = [
                    nil, .queued, .sending, .delivered,
                ]
                for tail in tails {
                    XCTAssertNotEqual(
                        text(phase: phase, runID: runID,
                             tail: tail),
                        "正在生成…",
                        "非生成相 \(phase) 产出了生成文案"
                    )
                }
            }
        }
    }

    // MARK: - 增补钉（断网规格）：未确认谓词

    /// 规格 5.3：isUnconfirmedSend 只认发送状态机
    /// ——队列四态为真、失败/已投递/无状态为假；
    /// 高度快照同源派生同值。sendStateMark 时钟读
    /// 口改挂本谓词（呈现面在屏断言受可达面所限列
    /// 真机门，判据本体在此钉死）
    func testIsUnconfirmedSendPredicate() throws {
        let container = try makeContainer()
        let thread = try seedThread(in: container, entries: [
            ("user", "谓词钉条目"),
        ])
        let context = ModelContext(container)
        let fetched = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        let entry = try XCTUnwrap(fetched.first?.sortedEntries.first)
        // 无状态：假
        XCTAssertFalse(entry.isUnconfirmedSend)
        // 队列四态：真
        for state in [
            ChatSendState.queued, .uploading, .linking,
            .sending,
        ] {
            entry.markSendState(state, in: context)
            XCTAssertTrue(
                entry.isUnconfirmedSend,
                "\(state) 应为未确认"
            )
            XCTAssertTrue(
                ChatEntryHeightSnapshot(entry)
                    .isUnconfirmedSend,
                "\(state) 快照派生应同值"
            )
        }
        // 失败：红感叹号分工、谓词为假（泡体回常色）
        entry.markSendState(.failed, in: context)
        XCTAssertTrue(entry.sendFailed)
        XCTAssertFalse(entry.isUnconfirmedSend)
        // 已投递：假
        entry.markSendState(.delivered, in: context)
        XCTAssertFalse(entry.isUnconfirmedSend)
        _ = thread
    }
}
