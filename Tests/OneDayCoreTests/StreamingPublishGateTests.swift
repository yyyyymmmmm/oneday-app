import XCTest
@testable import OneDayCore

/// §494（2026-11-24）流式发布门钉测：节流双
/// 触发（N 字／M 秒）／渲染下限／单拍步进上
/// 限追赶／首拍直发／flush 落定逐字一致／快
/// 照前缀单调／断流恢复回放拼接（装配器 res-
/// tore 续喂后最终快照与连续喂入逐字相同）
final class StreamingPublishGateTests: XCTestCase {

    private func text(_ n: Int) -> String {
        String(repeating: "字", count: n)
    }

    // MARK: - 首拍直发

    func testFirstPublishIsImmediateAndFull() {
        var gate = StreamingPublishGate()
        let snapshot = gate.offer("你好", now: 100)
        XCTAssertEqual(snapshot, "你好")
        XCTAssertEqual(gate.publishedText, "你好")
        XCTAssertEqual(gate.publishCount, 1)
        XCTAssertFalse(gate.hasUnpublished)
    }

    // MARK: - 节流双触发

    func testSmallBacklogWaitsForTimeTrigger() {
        var gate = StreamingPublishGate()
        _ = gate.offer(text(10), now: 0)
        // 积压 10 字 < N：字符触发不到；90ms 内
        // 时间触发也不到 → 不发布
        XCTAssertNil(gate.offer(text(20), now: 0.05))
        XCTAssertEqual(gate.publishedText, text(10))
        // 满 90ms：时间触发发布全部积压
        let snapshot = gate.tick(now: 0.09)
        XCTAssertEqual(snapshot, text(20))
    }

    func testCharTriggerNeedsMinInterval() {
        var gate = StreamingPublishGate()
        _ = gate.offer(text(10), now: 0)
        // 积压 ≥N（80）但距上拍 <50ms：渲染下限
        // 拦住，不许超 20Hz 发布
        XCTAssertNil(gate.offer(text(100), now: 0.03))
        // 满 50ms：字符触发发布（积压 90 ≤ 步进
        // 上限，全量）
        let snapshot = gate.offer(text(100), now: 0.05)
        XCTAssertEqual(snapshot, text(100))
    }

    func testNoBacklogNoPublish() {
        var gate = StreamingPublishGate()
        _ = gate.offer("abc", now: 0)
        XCTAssertNil(gate.tick(now: 10))
        XCTAssertNil(gate.offer("abc", now: 10))
        XCTAssertEqual(gate.publishCount, 1)
    }

    // MARK: - 步进上限与追赶

    func testBurstBacklogCatchesUpByCappedSteps() {
        var gate = StreamingPublishGate()
        _ = gate.offer(text(5), now: 0)
        // 突发积压 1000 字：每拍至多前进 120 字
        var now = 0.0
        var lastCount = gate.publishedText.count
        var steps = 0
        _ = gate.offer(text(1005), now: 0.01)
        while gate.hasUnpublished, steps < 50 {
            now += 0.1
            let snapshot = gate.tick(now: now)
            XCTAssertNotNil(snapshot)
            let advanced = (snapshot?.count ?? 0) - lastCount
            XCTAssertLessThanOrEqual(
                advanced, StreamingPublishGate.maxStep,
                "单拍步进不许超上限")
            XCTAssertGreaterThan(advanced, 0)
            lastCount = snapshot?.count ?? lastCount
            steps += 1
        }
        XCTAssertFalse(gate.hasUnpublished)
        XCTAssertEqual(gate.publishedText, text(1005))
        XCTAssertGreaterThan(steps, 5, "1000 字积压须多拍追赶")
    }

    // MARK: - 前缀单调＋落定逐字一致（装配器联动）

    func testSnapshotsArePrefixesAndFinalFlushMatchesAssembler() {
        var assembler = StreamSegmentAssembler()
        var gate = StreamingPublishGate()
        let deltas = [
            "第一段", "继续生长", "，直到工具打断",
            "新段开始", "，收尾",
        ]
        var now = 0.0
        var snapshots: [String] = []
        // 第一段三增量后封段（工具边界），再喂第
        // 二段两增量——全程快照须为最终全文前缀
        for (index, delta) in deltas.enumerated() {
            assembler.offer(delta)
            if index == 2 {
                XCTAssertNotNil(assembler.sealCurrentSegment())
                if let sealed = gate.flush() {
                    snapshots.append(sealed)
                }
            }
            now += 0.1
            if let snapshot = gate.offer(
                assembler.mergedFullText, now: now
            ) {
                snapshots.append(snapshot)
            }
        }
        if let final = gate.flush() {
            snapshots.append(final)
        }
        let expected = assembler.mergedFullText
        XCTAssertEqual(snapshots.last, expected)
        XCTAssertEqual(
            expected, "第一段继续生长，直到工具打断\n\n新段开始，收尾")
        for snapshot in snapshots {
            XCTAssertTrue(
                expected.hasPrefix(snapshot),
                "快照必须是最终全文的前缀：\(snapshot)")
        }
        for pair in zip(snapshots, snapshots.dropFirst()) {
            XCTAssertTrue(
                pair.1.hasPrefix(pair.0),
                "快照序列必须单调生长")
        }
        // 落定对账：flush 后已发布与装配器兜底全
        // 文逐字相等
        XCTAssertEqual(gate.publishedText, expected)
    }

    // MARK: - 断流恢复回放拼接

    func testReplaySpliceAfterRestoreConvergesToSameText() {
        // 连续路：一段到底喂完
        var continuous = StreamSegmentAssembler()
        var continuousGate = StreamingPublishGate()
        let partA = ["甲段起手", "，继续"]
        let partB = ["，工具后新段", "，收尾"]
        for delta in partA { continuous.offer(delta) }
        continuous.sealCurrentSegment()
        for delta in partB { continuous.offer(delta) }
        _ = continuousGate.offer(continuous.mergedFullText, now: 0)
        _ = continuousGate.flush()

        // 断流路：A 段落盘 → restore 回填（封存
        // 段＋打开段）→ 重挂后续喂 B 段
        var restored = StreamSegmentAssembler()
        restored.restore(
            sealed: ["甲段起手，继续"], current: "")
        // restore 后打开段为空：B 段增量进新段；
        // 先封空段（无段可封、空转）再喂
        _ = restored.sealCurrentSegment()
        for delta in partB { restored.offer(delta) }
        var restoredGate = StreamingPublishGate()
        _ = restoredGate.offer(restored.mergedFullText, now: 0)
        _ = restoredGate.flush()

        XCTAssertEqual(
            restored.mergedFullText, continuous.mergedFullText)
        XCTAssertEqual(
            restoredGate.publishedText,
            continuousGate.publishedText)
    }

    /// 重挂回放把已收增量按 seq 续后重发一遍的
    /// 拼接形态：装配器只收续段（回放不重发已
    /// 确认增量是客户端 lastSeq 的既有口径），
    /// 发布门对「已发布前缀＋续长全文」的 offer
    /// 保持前缀不变量、不重置
    func testGateKeepsPrefixAcrossRehangContinuation() {
        var gate = StreamingPublishGate()
        _ = gate.offer("前半段", now: 0)
        // 断流后重挂：全文＝已发布前缀＋续长
        let snapshot = gate.offer("前半段后半段", now: 0.1)
        XCTAssertEqual(snapshot, "前半段后半段")
        XCTAssertEqual(gate.publishCount, 2)
    }

    // MARK: - 非追加形态自重置

    func testDivergentTargetResetsAndRepublishes() {
        var gate = StreamingPublishGate()
        _ = gate.offer("原文一段", now: 0)
        // 全文被改写（与已发布无前缀关系）：整门
        // 重置、按首拍全量重发新文
        let snapshot = gate.offer("完全不同的新文", now: 0.01)
        XCTAssertEqual(snapshot, "完全不同的新文")
        XCTAssertEqual(gate.publishedText, "完全不同的新文")
    }

    func testResetClearsEverything() {
        var gate = StreamingPublishGate()
        _ = gate.offer(text(50), now: 0)
        gate.reset()
        XCTAssertEqual(gate.publishedText, "")
        XCTAssertEqual(gate.publishCount, 0)
        XCTAssertFalse(gate.hasUnpublished)
        // 重置后首拍直发恢复
        XCTAssertEqual(gate.offer("新轮", now: 1), "新轮")
    }
}
