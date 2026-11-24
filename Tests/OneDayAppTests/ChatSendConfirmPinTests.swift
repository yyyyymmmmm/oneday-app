import OneDayCore
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §426（缺陷一＋缺陷四）呈现层钉测：
/// 缺陷一——未确认气泡的浅色/时钟读数只认呈现
/// 单源（ChatView.userBubbleOpacity /
/// sendStateMarkKind），逐发送状态断言读数；受
/// 理转换（受理点同款 markSendState(.delivered)）
/// 落下后、整轮尚未落定（无 serverRowID、无落
/// 定条目）时读数即翻全色/无标记——旧链该转换
/// 只在落定点发生、生成全程读数恒浅色＋时钟
/// （用户真机截图）。
/// 缺陷四——占位行视觉形态与文案单源全组合一
/// 致性：三点恰对应已受理四文案、未受理恒文字
/// 且文案恰「等待发送…」；三点动画测状态（相
/// 位/周期/幅度/静止档）不测像素。
@MainActor
final class ChatSendConfirmPinTests: XCTestCase {

    // MARK: - 装配（与 ChatFailKeepPinTests 同式）

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([ChatThread.self, ChatEntry.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true
            )]
        )
    }

    private func seedEntry(
        in container: ModelContainer
    ) throws -> (entry: ChatEntry, context: ModelContext) {
        let context = ModelContext(container)
        let thread = ChatThread(title: "426 钉测线程")
        context.insert(thread)
        let entry = ChatEntry(
            role: "user", content: "你好", thread: thread
        )
        context.insert(entry)
        try context.save()
        let fetched = try context.fetch(
            FetchDescriptor<ChatThread>()
        )
        return (
            try XCTUnwrap(fetched.first?.sortedEntries.first),
            context
        )
    }

    private func readings(
        for entry: ChatEntry
    ) -> (opacity: Double, mark: ChatView.SendStateMarkKind) {
        (
            ChatView.userBubbleOpacity(
                isUnconfirmedSend: entry.isUnconfirmedSend
            ),
            ChatView.sendStateMarkKind(
                sendFailed: entry.sendFailed,
                isUnconfirmedSend: entry.isUnconfirmedSend
            )
        )
    }

    // MARK: - 缺陷一：逐态呈现读数

    func testBubbleReadingsPerSendState() throws {
        let container = try makeContainer()
        let (entry, context) = try seedEntry(in: container)
        // 无状态：已确认口径（全色、无标记）
        var result = readings(for: entry)
        XCTAssertEqual(result.opacity, 1)
        XCTAssertEqual(result.mark, .none)
        // 队列四态：浅色 0.45＋时钟
        for state in [
            ChatSendState.queued, .uploading, .linking, .sending,
        ] {
            entry.markSendState(state, in: context)
            result = readings(for: entry)
            XCTAssertEqual(
                result.opacity, 0.45,
                "\(state) 应浅色"
            )
            XCTAssertEqual(
                result.mark, .clock,
                "\(state) 应挂时钟"
            )
        }
        // 失败：泡体回全色、标记换红叹号
        entry.markSendState(.failed, in: context)
        result = readings(for: entry)
        XCTAssertEqual(result.opacity, 1)
        XCTAssertEqual(result.mark, .failure)
        // 已投递：全色、无标记
        entry.markSendState(.delivered, in: context)
        result = readings(for: entry)
        XCTAssertEqual(result.opacity, 1)
        XCTAssertEqual(result.mark, .none)
    }

    /// 受理转换在「生成仍在飞」时落下：条目只走
    /// 受理点同款一笔（delivered），不经落定（不
    /// 钉 serverRowID、不产落定条目）——读数必须
    /// 立刻翻正。这正是用户口径：服务器确认收到
    /// ＝发送成功，不等回复完成
    func testAcceptanceFlipsReadingsBeforeSettlement() throws {
        let container = try makeContainer()
        let (entry, context) = try seedEntry(in: container)
        entry.markSendState(.sending, in: context)
        XCTAssertEqual(readings(for: entry).opacity, 0.45)
        XCTAssertEqual(readings(for: entry).mark, .clock)
        // 受理点同款转换（markAcceptedEntryDelivered
        // 的本体一笔）
        entry.markSendState(.delivered, in: context)
        XCTAssertNil(
            entry.serverRowID,
            "受理≠落定：服务端行 id 尚未钉桩（落定点职责）"
        )
        let result = readings(for: entry)
        XCTAssertEqual(
            result.opacity, 1,
            "受理后气泡应立即全色（不等落定）"
        )
        XCTAssertEqual(
            result.mark, .none,
            "受理后时钟应离席"
        )
    }

    /// 断网未受理：保持浅色＋时钟（§414 断网口径
    /// 不许被受理改判误伤）
    func testOfflineUnacceptedKeepsReadings() throws {
        let container = try makeContainer()
        let (entry, context) = try seedEntry(in: container)
        entry.markPendingSend(in: context)
        let result = readings(for: entry)
        XCTAssertEqual(result.opacity, 0.45)
        XCTAssertEqual(result.mark, .clock)
    }

    // MARK: - 缺陷四：占位行视觉形态全组合对账

    func testPlaceholderVisualMatchesStatusTextFamily() {
        let acceptedTexts: Set<String> = [
            "正在生成…", "正在思考…", "正在调用工具…",
            "正在确认结果…",
        ]
        let phases: [RunTurnPhase] = [
            .submitting, .generating(stopping: false),
            .generating(stopping: true),
            .unknown, .reconciling, .finished, .failed,
        ]
        let tails: [ChatSendState?] = [
            nil, .queued, .uploading, .linking, .sending,
            .failed, .delivered,
        ]
        for phase in phases {
            for runID in [false, true] {
                for tail in tails {
                    for uploading in [false, true] {
                        let text = ChatView.placeholderStatusText(
                            phase: phase,
                            runIDEstablished: runID,
                            tailSendState: tail,
                            isUploading: uploading,
                            uploadFraction: uploading ? 0.5 : nil,
                            hasReasoning: false,
                            hasToolCards: false
                        )
                        let visual = ChatView.placeholderVisual(
                            phase: phase,
                            runIDEstablished: runID,
                            tailSendState: tail,
                            isUploading: uploading
                        )
                        if acceptedTexts.contains(text) {
                            XCTAssertEqual(
                                visual, .typingDots,
                                "已受理文案「\(text)」应显三点 "
                                    + "(phase=\(phase) runID=\(runID) "
                                    + "tail=\(String(describing: tail)))"
                            )
                        } else {
                            XCTAssertEqual(
                                visual, .statusText,
                                "未受理文案「\(text)」应显文字 "
                                    + "(phase=\(phase) runID=\(runID) "
                                    + "tail=\(String(describing: tail)))"
                            )
                        }
                    }
                }
            }
        }
    }

    /// 未受理两向钉死：断网未确立＝「等待发送…」
    /// 文字在席、三点不在席；生成相＝三点在席
    func testPlaceholderVisualKeyPhases() {
        XCTAssertEqual(
            ChatView.placeholderVisual(
                phase: .submitting, runIDEstablished: false,
                tailSendState: .sending, isUploading: false
            ),
            .statusText
        )
        XCTAssertEqual(
            ChatView.placeholderStatusText(
                phase: .submitting, runIDEstablished: false,
                tailSendState: .sending, isUploading: false,
                uploadFraction: nil, hasReasoning: false,
                hasToolCards: false
            ),
            "等待发送…"
        )
        XCTAssertEqual(
            ChatView.placeholderVisual(
                phase: .generating(stopping: false),
                runIDEstablished: true,
                tailSendState: .delivered, isUploading: false
            ),
            .typingDots
        )
        // 上传段是未受理家族：文字在席
        XCTAssertEqual(
            ChatView.placeholderVisual(
                phase: .submitting, runIDEstablished: false,
                tailSendState: .uploading, isUploading: true
            ),
            .statusText
        )
    }

    // MARK: - 缺陷四：三点动画状态（不测像素）

    func testTypingDotsAnimationState() {
        // iMessage 口径落数钉死（改数须同批改 §426）
        XCTAssertEqual(TypingDots.dotDiameter, 8)
        XCTAssertEqual(TypingDots.cycleDuration, 1.4)
        XCTAssertEqual(TypingDots.stagger, 0.22)
        // 幅度域：全程 ∈ [0.3, 1.0]
        for step in 0..<56 {
            let t = Double(step) * 0.025
            for index in 0..<3 {
                let value = TypingDots.opacity(
                    at: t, index: index, reduceMotion: false
                )
                XCTAssertGreaterThanOrEqual(value, 0.3)
                XCTAssertLessThanOrEqual(value, 1.0)
            }
        }
        // 错峰在走：同一时刻三点相位互异（t=0.35
        // 三值两两不等）
        let at35 = (0..<3).map {
            TypingDots.opacity(at: 0.35, index: $0, reduceMotion: false)
        }
        XCTAssertNotEqual(at35[0], at35[1])
        XCTAssertNotEqual(at35[1], at35[2])
        XCTAssertNotEqual(at35[0], at35[2])
        // 周期性：相隔恰一周期读数复现
        for t in [0.0, 0.35, 0.9] {
            for index in 0..<3 {
                XCTAssertEqual(
                    TypingDots.opacity(
                        at: t, index: index, reduceMotion: false
                    ),
                    TypingDots.opacity(
                        at: t + TypingDots.cycleDuration,
                        index: index, reduceMotion: false
                    ),
                    accuracy: 1e-9
                )
            }
        }
        // Reduce Motion：静止恒值
        for index in 0..<3 {
            XCTAssertEqual(
                TypingDots.opacity(
                    at: 0.35, index: index, reduceMotion: true
                ),
                0.6
            )
        }
    }

    // MARK: - 缺陷二：前台消账的 App 侧合成

    private func runNotification(
        id: String, session: String?, read: Bool = false,
        kind: String = "task_completed"
    ) -> OverviewNotification {
        OverviewNotification(
            id: id, kind: kind, title: "运行完成",
            body: "一轮运行已完成",
            createdAt: "2026-11-24T00:00:00+08:00",
            read: read, refId: session
        )
    }

    /// 活动会话终态：消账后卡不现、记录仍在名单；
    /// 非活动会话终态：卡照现（基线行为不许改坏）
    func testForegroundRunResolutionSuppressesCardKeepsRecord() async {
        let store = OverviewBridgeStore()
        let mine = runNotification(id: "run-1", session: "sess-open")
        let other = runNotification(id: "run-2", session: "sess-other")
        store.installLoadedNotifications([mine, other])
        let resolved = RunCompletionResolution.receiptsToResolve(
            notifications: store.notifications,
            foregroundServerSessionID: "sess-open"
        )
        XCTAssertEqual(resolved, ["run-1"])
        for id in resolved {
            await store.markRead(appState: AppState(), id: id)
        }
        // 记录保留：两条都还在名单里，只翻已读
        XCTAssertEqual(store.notifications.count, 2)
        XCTAssertEqual(
            store.notifications.map(\.read), [true, false]
        )
        // 卡面：活动会话的不现、其他会话的照现
        let cards = ReportCardPolicy.cards(
            notifications: store.notifications, isMainThread: true
        )
        XCTAssertEqual(cards.map(\.id), ["run-2"])
    }
}
