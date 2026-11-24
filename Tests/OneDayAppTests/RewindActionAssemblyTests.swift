import OneDayCore
import XCTest
@testable import OneDayApp

/// D3/D2 组装＋门控＋切分钉测（DESIGN §352）：动
/// 作面项集/序、门控谓词真值表、轮次切分纯函数
/// ——三处都是「错一格截错一轮」的高危逻辑，逐格
/// 钉死；网络编排由 Core 分类矩阵把守（Rewind-
/// ContractTests），真机流按施工图 §十留用户
@MainActor
final class RewindActionAssemblyTests: XCTestCase {

    // MARK: - 组装（actionItems 单源）

    private func makeData(
        plainText: String = "正文",
        outbox: Bool = false,
        editSent: Bool = false,
        regenerate: Bool = false,
        speak: Bool = false
    ) -> ChatRowActionSheetData {
        // makeSpeakItem 是 @MainActor 闭包型：先以显式
        // 类型落到局部量再传入参——三元内联闭包会让类
        // 型检查器放弃诊断（failed to produce diagnostic）
        let speakProvider: (@MainActor () -> ChatRowSpeakItem?)?
        if speak {
            speakProvider = {
                ChatRowSpeakItem(
                    title: "朗读",
                    systemImage: MessageActionSymbols.speak,
                    action: {}
                )
            }
        } else {
            speakProvider = nil
        }
        return ChatRowActionSheetData(
            plainText: plainText,
            canReact: false, ownEmoji: nil,
            onPickReaction: { _ in },
            onReply: {}, onFork: {},
            onSelect: {}, onShare: {},
            onResend: outbox ? {} : nil,
            onEditUnsent: outbox ? {} : nil,
            onWithdrawUnsent: outbox ? {} : nil,
            onEditSent: editSent ? {} : nil,
            onRegenerate: regenerate ? {} : nil,
            makeSpeakItem: speakProvider
        )
    }

    func testEditSentSitsAfterForkBeforeCopy() {
        let items = makeData(editSent: true).actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.reply, .fork, .editSent, .copy, .select, .share]
        )
        XCTAssertEqual(
            items.first { $0.kind == .editSent }?.title, "编辑"
        )
        XCTAssertEqual(
            items.first { $0.kind == .editSent }?.systemImage,
            MessageActionSymbols.editUnsent
        )
    }

    func testRegenerateSitsWithEditGroupAndSpeakStaysLast() {
        let items = makeData(
            regenerate: true, speak: true
        ).actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.reply, .fork, .regenerate, .copy, .select,
             .share, .speak]
        )
        XCTAssertEqual(items.last?.kind, .speak)
    }

    func testOutboxNeverAssemblesEditOrRegenerate() {
        // 互斥在席：发件箱条目即便误注入两闭包，组装
        // 侧也不许两套项集同席
        let items = makeData(
            outbox: true, editSent: true, regenerate: true
        ).actionItems()
        XCTAssertFalse(items.contains { $0.kind == .editSent })
        XCTAssertFalse(items.contains { $0.kind == .regenerate })
        XCTAssertEqual(
            items.map(\.kind),
            [.resend, .editUnsent, .copy, .select, .share,
             .withdrawUnsent]
        )
    }

    func testSettledWithoutClosuresKeepsLegacySet() {
        let items = makeData().actionItems()
        XCTAssertEqual(
            items.map(\.kind),
            [.reply, .fork, .copy, .select, .share]
        )
    }

    // MARK: - 门控谓词真值表

    private func entry(
        role: String, rowID: Int? = nil
    ) -> ChatEntry {
        let entry = ChatEntry(role: role, content: "正文")
        entry.serverRowID = rowID
        return entry
    }

    func testCanEditSentTruthTable() {
        XCTAssertTrue(entry(role: "user", rowID: 11).canEditSent)
        // 未钉桩（本地出生未上行）：rewind 无的放矢
        XCTAssertFalse(entry(role: "user").canEditSent)
        // 角色不对
        XCTAssertFalse(
            entry(role: "assistant", rowID: 11).canEditSent
        )
        // 待发/失败不是已落定
        let pending = entry(role: "user", rowID: 11)
        pending.deliveryState = "pending"
        XCTAssertFalse(pending.canEditSent)
        let failed = entry(role: "user", rowID: 11)
        failed.sendFailed = true
        XCTAssertFalse(failed.canEditSent)
        // 发送队列未落定态（queued）不是已落定
        let queued = entry(role: "user", rowID: 11)
        queued.sendStateRaw = ChatSendState.queued.rawValue
        XCTAssertFalse(queued.canEditSent)
        // 已投递态可编辑
        let delivered = entry(role: "user", rowID: 11)
        delivered.sendStateRaw = ChatSendState.delivered.rawValue
        XCTAssertTrue(delivered.canEditSent)
        // 系统锚定行不出
        let anchored = ChatEntry(
            role: "user", content: "正文", echoKey: "e1"
        )
        anchored.serverRowID = 11
        XCTAssertFalse(anchored.canEditSent)
    }

    func testCanRegenerateCandidateTruthTable() {
        XCTAssertTrue(
            entry(role: "assistant", rowID: 12)
                .canRegenerateCandidate
        )
        XCTAssertFalse(
            entry(role: "user", rowID: 12)
                .canRegenerateCandidate
        )
        let pending = entry(role: "assistant", rowID: 12)
        pending.deliveryState = "pending"
        XCTAssertFalse(pending.canRegenerateCandidate)
    }

    // MARK: - 轮次切分

    private func turn(
        _ userRow: Int, _ assistantRow: Int
    ) -> [ChatEntry] {
        [
            entry(role: "user", rowID: userRow),
            entry(role: "assistant", rowID: assistantRow),
        ]
    }

    func testSlicingTailPredecessorAndRounds() {
        let entries = turn(101, 102) + turn(103, 104)
            + turn(105, 106)
        let target = entries[2]  // 第二轮 user(103)
        XCTAssertEqual(
            RewindTurnSlicing.tail(
                from: target.id, in: entries
            ).map(\.serverRowID),
            [103, 104, 105, 106]
        )
        XCTAssertEqual(
            RewindTurnSlicing.predecessorRowID(
                before: target.id, in: entries
            ),
            102
        )
        XCTAssertEqual(
            RewindTurnSlicing.roundsAfter(
                target: target.id, in: entries
            ),
            1
        )
        // 末轮 user：0 轮＝不弹确认直走
        XCTAssertEqual(
            RewindTurnSlicing.roundsAfter(
                target: entries[4].id, in: entries
            ),
            0
        )
        // 首轮 user：无前行＝截断后尾应为空
        XCTAssertNil(
            RewindTurnSlicing.predecessorRowID(
                before: entries[0].id, in: entries
            )
        )
    }

    func testRegenerationTurnTargetsUserRowNeverAssistant() {
        let entries = turn(101, 102) + turn(103, 104)
        let lastAssistant = entries[3]
        let turnSlice = RewindTurnSlicing.regenerationTurn(
            assistant: lastAssistant.id, in: entries
        )
        XCTAssertEqual(turnSlice?.user.serverRowID, 103)
        XCTAssertEqual(
            turnSlice?.segment.map(\.serverRowID), [104]
        )
        // 最后一条已落定助手条目的呈现时刻判定
        XCTAssertEqual(
            RewindTurnSlicing.lastSettledAssistant(
                in: entries
            )?.id,
            lastAssistant.id
        )
    }

    func testRegenerationTurnNilWhenUserRowUnpinned() {
        // user 行未钉桩：rewind 无的放矢，整流不出
        let entries = [
            entry(role: "user"),
            entry(role: "assistant", rowID: 202),
        ]
        XCTAssertNil(
            RewindTurnSlicing.regenerationTurn(
                assistant: entries[1].id, in: entries
            )
        )
    }
}
