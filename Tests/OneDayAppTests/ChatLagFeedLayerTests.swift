import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// 2026-11-20 卡顿修复包回归闸（全面对比报告
/// chat-lag-full-comparison-20261120 §2/§3/§6/§8）：
/// ①行描述备忘——未变行零重建、戳变才重建、清
/// 账后不复用；②修订摘要制——parts 不载正文/图
/// 本体、派生确定且全字段敏感；③流式逐块沉淀
/// ——尾块生长/新块闭合不改已闭合块的呈现源；
/// ④直播行高确定性与尾块增量（③④§409 步 D
/// 退役）；⑤探针计数可回
/// 读；⑥每遍成本对比 harness（长会话回放：旧式
/// 全量入账载荷 vs 摘要制载荷＋第二趟重建数，
/// 数值 print 进 CI 日志作实验室口径对账，非真
/// 机帧率）
@MainActor
final class ChatLagFeedLayerTests: XCTestCase {

    // MARK: - ① 行描述备忘

    private func makeRow(_ key: String) -> ChatNativeRow {
        ChatNativeRow(
            key: key, entryID: nil,
            makeView: { AnyView(EmptyView()) }
        )
    }

    func testUnchangedRowIsNotRebuilt() {
        let memo = ChatNativeRowDescriptorMemo()
        var builds = 0
        func build(_ key: String) -> ChatNativeRow {
            builds += 1
            return makeRow(key)
        }
        _ = memo.row(key: "entry-a", stamp: "s1") {
            build("entry-a")
        }
        _ = memo.row(key: "entry-a", stamp: "s1") {
            build("entry-a")
        }
        XCTAssertEqual(
            builds, 1,
            "同键同戳第二趟必须整行复用、零重建"
        )
        XCTAssertEqual(memo.buildCount, 1)
        XCTAssertEqual(memo.reuseCount, 1)
        // 戳变（内容/高度/点亮任一变）→ 重建
        _ = memo.row(key: "entry-a", stamp: "s2") {
            build("entry-a")
        }
        XCTAssertEqual(builds, 2, "戳变必须重建")
        // 清账未保留的键 → 不许复用陈账
        memo.prune(keeping: ["entry-b"])
        _ = memo.row(key: "entry-a", stamp: "s2") {
            build("entry-a")
        }
        XCTAssertEqual(builds, 3, "清账后的行必须重建")
        // 他行在席不影响本行复用
        _ = memo.row(key: "entry-b", stamp: "s1") {
            build("entry-b")
        }
        _ = memo.row(key: "entry-b", stamp: "s1") {
            build("entry-b")
        }
        XCTAssertEqual(builds, 4)
    }

    // MARK: - ② 修订摘要制

    func testRevisionPartsCarryDigestsNotFullText() throws {
        let longText = String(
            repeating: "这是一段很长的助手正文，用来验证修订不再逐字入账。",
            count: 40
        )
        let imageBytes = Data(
            (0..<50_000).map { UInt8($0 % 251) }
        )
        let entry = ChatEntry(
            role: "assistant", content: longText,
            thread: nil
        )
        entry.imageData = imageBytes
        let revision = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil, highlighted: false,
            styleKey: "style-a"
        )
        var textPayload = 0
        var dataPayload = 0
        for part in revision.parts {
            switch part {
            case .text(let string):
                textPayload += string.utf8.count
                XCTAssertFalse(
                    string.contains("这是一段很长的助手正文"),
                    "修订 text 项不许载正文本体（须为长度＋哈希摘要）"
                )
            case .data(let data):
                dataPayload += data.count
                XCTAssertEqual(
                    data.count, 16,
                    "修订 data 项须为 16 字节定长摘要（长度＋采样哈希）"
                )
            case .flag, .count, .real:
                break
            }
        }
        XCTAssertLessThan(
            textPayload, 2_000,
            "全文 \(longText.count) 字的修订 text 载荷须为摘要量级"
        )
        XCTAssertLessThan(
            dataPayload, 100,
            "50KB 图数据的修订 data 载荷须为定长摘要量级"
        )
        // 确定性与敏感性（与 R3 全字段敏感测试同口径）
        let again = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil, highlighted: false,
            styleKey: "style-a"
        )
        XCTAssertEqual(revision, again)
        entry.content = longText + "多一字"
        let changed = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil, highlighted: false,
            styleKey: "style-a"
        )
        XCTAssertNotEqual(revision, changed)
        // 数据本体同长度异内容（采样窗内）→ 摘要须变
        entry.imageData = Data(
            (0..<50_000).map { UInt8(($0 + 1) % 251) }
        )
        let dataChanged = ChatNativeRowRevision.entry(
            entry,
            dividerText: nil, highlighted: false,
            styleKey: "style-a"
        )
        XCTAssertNotEqual(changed, dataChanged)
    }

    /// 基段单点：entry 与 entryMemoKey 的中性派生
    /// 共用 entryBase——基段＋中性尾段须与合成器
    /// entryMemoKey(for:) 逐字同键（两路同键是量
    /// 测台对账的前提）
    func testEntryMemoKeyBaseRevisionMatchesLegacyPath() {
        let composer = makeComposer()
        let entry = ChatEntry(
            role: "assistant",
            content: "量测键对账样本正文。",
            thread: nil
        )
        let legacy = composer.entryMemoKey(
            for: entry, dividerText: "今天 09:41",
            showsUnreadDivider: true
        )
        let base = ChatNativeRowRevision.entryBase(
            entry,
            dividerText: "今天 09:41",
            showsUnreadDivider: true
        )
        let viaBase = composer.entryMemoKey(
            baseRevision: base, entry: entry
        )
        XCTAssertEqual(
            legacy, viaBase,
            "基段入参版与原路径必须逐字同键"
        )
    }

    // MARK: - ④ 直播行高（§409 步 D 退役；下方合成器工厂供 ② 复用）

    private func makeComposer()
        -> ChatNativeRowHeightComposer
    {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ChatRowStateLedger(),
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    // MARK: - ⑤ 探针回读

    func testProbeCountersAccumulate() {
        ChatLagProbe.reset()
        ChatLagProbe.noteDecode(
            duration: .milliseconds(5)
        )
        let token = ChatLagProbe.beginFeedPass()
        ChatLagProbe.endFeedPass(
            token, built: 3, reused: 7, streaming: true
        )
        let line = ChatLagProbe.summaryLine()
        XCTAssertTrue(
            line.contains("feed 1趟 建3 复用7"),
            "喂入计数须可回读：\(line)"
        )
        XCTAssertTrue(
            line.contains("解码 1次"),
            "解码计数须可回读：\(line)"
        )
        ChatLagProbe.reset()
        XCTAssertTrue(
            ChatLagProbe.summaryLine()
                .contains("feed 0趟")
        )
    }

    // MARK: - ⑥ 每遍成本对比 harness（实验室口径）

    /// 长会话回放：第 1 趟全建、第 2 趟只改尾条目
    /// ——旧式（无备忘）每趟全建 N 行，新式第 2 趟
    /// 只许建 1 行；修订载荷旧式＝语料本体、新式
    /// ＝摘要定长。数值 print 作交卷对账（实验室
    /// 口径、非真机帧率）
    func testPerPassCostComparisonHarness() {
        let entryCount = 120
        let body = String(
            repeating: "长会话回放样本正文，模拟千字级助手回复的语料量。",
            count: 100
        )
        var entries: [ChatEntry] = []
        for index in 0..<entryCount {
            let entry = ChatEntry(
                role: index % 2 == 0
                    ? "assistant" : "user",
                content: body + "（第\(index)条）",
                thread: nil
            )
            if index % 5 == 0 {
                entry.imageData = Data(
                    repeating: 0xAB, count: 20_000
                )
            }
            entries.append(entry)
        }
        func payloadBytes(
            _ revision: ChatNativeRowRevision
        ) -> Int {
            revision.parts.reduce(0) { sum, part in
                switch part {
                case .text(let string):
                    return sum + string.utf8.count
                case .data(let data):
                    return sum + data.count
                case .flag, .count, .real:
                    return sum + 8
                }
            }
        }
        // 旧式载荷：正文全文＋图本体逐字入账的等价
        // 量（旧 addText/addData 的入账口径直算）
        var legacyPayload = 0
        var digestPayload = 0
        let memo = ChatNativeRowDescriptorMemo()
        func pass(measurePayload: Bool) -> Int {
            var builtThisPass = 0
            for (index, entry) in entries.enumerated() {
                let revision = ChatNativeRowRevision
                    .entry(
                        entry,
                        dividerText: nil,
                        highlighted: false,
                        styleKey: "style-a"
                    )
                if measurePayload {
                    legacyPayload += entry.content.utf8.count
                        + (entry.imageData?.count ?? 0)
                    digestPayload += payloadBytes(revision)
                }
                let stamp = "\(revision.hashValue)"
                let before = memo.buildCount
                _ = memo.row(
                    key: "entry-\(index)", stamp: stamp
                ) {
                    ChatNativeRow(
                        key: "entry-\(index)",
                        entryID: entry.id,
                        revision: revision,
                        makeView: { AnyView(EmptyView()) }
                    )
                }
                builtThisPass += memo.buildCount - before
            }
            memo.prune(
                keeping: Set(
                    entries.indices.map { "entry-\($0)" }
                )
            )
            return builtThisPass
        }
        let pass1Built = pass(measurePayload: true)
        // 第二趟前只动尾条目正文（修订真变、余行逐
        // 字不变）
        entries[entryCount - 1].content += "改"
        let pass2Built = pass(measurePayload: false)
        print(
            "[lag-harness] 行数 \(entryCount)"
                + "｜第1趟建 \(pass1Built) 行"
                + "｜第2趟（只改尾条目）建 \(pass2Built) 行"
                + "（旧式每趟全建 \(entryCount) 行）"
                + "｜修订载荷 旧式 \(legacyPayload)B"
                + " vs 摘要制 \(digestPayload)B"
        )
        XCTAssertEqual(pass1Built, entryCount)
        XCTAssertEqual(
            pass2Built, 1,
            "第二趟只改一行时只许重建一行（未变行零重建）"
        )
        XCTAssertLessThan(
            digestPayload, legacyPayload / 10,
            "摘要制修订载荷须比全量入账低一个数量级"
        )
    }
}
