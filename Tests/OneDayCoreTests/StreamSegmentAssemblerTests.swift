import OneDayCore
import XCTest

/// 流式分段装配（第 93 条；§409 步 E 随闸瘦身为
/// 纯累积）：确定性回放「文字段 A→工具调用→文字
/// 段 B」钉死跨段不串字——B 的当前段只含 B、A 只
/// 在封存列出现一次；段内累积逐字精确；合并全文
/// 与落定拼接（"\n\n"）同制。旧发布语义钉测（窗
/// 口合并/巡查/新段首字立即发布）随步 E 退役——
/// 累积器无发布态，每拍入账即精确。
final class StreamSegmentAssemblerTests: XCTestCase {

    /// 第 93 条事故原文回放：A＝落库 4640 段全文、
    /// B＝4643 段全文（主线服务端取证原样），分片
    /// 喂入＋工具边界封段后逐项对账
    func testIncidentReplaySegmentsDoNotCarryOver() {
        let segmentA = "好，我换个更可靠的方式——用 Replicate 的公开 "
            + "DeOldify 模型，不需要 API key 的那种，或者直接调一个免费的彩色化服务。"
        let segmentB = "好，我直接用 colorize.cc 或 DeepAI 的免费接口，不需要注册。先试 DeepAI。"
        var assembler = StreamSegmentAssembler()
        for chunk in ["好，我换个", "更可靠的方式——用 Replicate 的公开 ",
                      "DeOldify 模型，不需要 API key 的那种，",
                      "或者直接调一个免费的彩色化服务。"] {
            assembler.offer(chunk)
        }
        // 工具调用开始＝段边界：A 封存
        XCTAssertEqual(
            assembler.sealCurrentSegment(), segmentA
        )
        for chunk in ["好，我直接用 colorize.cc 或 ",
                      "DeepAI 的免费接口，不需要注册。先试 DeepAI。"] {
            assembler.offer(chunk)
        }
        // B 的当前段只有 B：不含 A 的任何一部分
        XCTAssertEqual(assembler.currentFullText, segmentB)
        XCTAssertFalse(assembler.currentFullText.hasPrefix("好，我换个"))
        // A 只出现一次、在封存列
        XCTAssertEqual(assembler.sealedSegments, [segmentA])
        XCTAssertEqual(
            assembler.fullSegments, [segmentA, segmentB]
        )
        // 合并全文与落定拼接同制（段间空行、逐字一致）
        XCTAssertEqual(
            assembler.mergedFullText,
            segmentA + "\n\n" + segmentB
        )
    }

    /// 段内累积逐字精确：无边界时每喂一拍当前段
    /// 全文即已喂分片的精确拼接，不攒压、不回退
    func testIntraSegmentAccumulationIsExact() {
        var assembler = StreamSegmentAssembler()
        var fed = ""
        for chunk in ["一", "二", "三", "四"] {
            assembler.offer(chunk)
            fed += chunk
            XCTAssertEqual(assembler.currentFullText, fed)
        }
        XCTAssertEqual(assembler.currentFullText, "一二三四")
        XCTAssertTrue(assembler.sealedSegments.isEmpty)
    }

    /// 封段后新段从空起步：首个增量只入新段、不
    /// 带上一段任何字
    func testNewSegmentStartsEmptyAfterSeal() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("甲")
        XCTAssertEqual(assembler.sealCurrentSegment(), "甲")
        assembler.offer("乙")
        XCTAssertEqual(assembler.currentFullText, "乙")
        XCTAssertEqual(assembler.fullSegments, ["甲", "乙"])
    }

    /// 空段不产出：工具先行（尚无正文）与并行工具
    /// 连发边界都无段可封、不产空段
    func testSealingEmptySegmentProducesNothing() {
        var assembler = StreamSegmentAssembler()
        XCTAssertNil(assembler.sealCurrentSegment())
        assembler.offer("正文")
        XCTAssertEqual(assembler.sealCurrentSegment(), "正文")
        // 紧接着的第二个边界（并行工具）：无段可封
        XCTAssertNil(assembler.sealCurrentSegment())
        XCTAssertEqual(assembler.sealedSegments, ["正文"])
        XCTAssertEqual(assembler.fullSegments, ["正文"])
    }

    /// 三段链：A→工具→B→工具→C，封存序与全文序
    /// 恒按事件序
    func testThreeSegmentsKeepEventOrder() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("A")
        assembler.sealCurrentSegment()
        assembler.offer("B")
        assembler.sealCurrentSegment()
        assembler.offer("C")
        XCTAssertEqual(assembler.sealedSegments, ["A", "B"])
        XCTAssertEqual(assembler.fullSegments, ["A", "B", "C"])
        XCTAssertEqual(assembler.mergedFullText, "A\n\nB\n\nC")
    }

    /// 封段取精确全文：段内最后一拍增量一并入段，
    /// 永不丢字、永不跨段漏字
    func testSealTakesExactFullText() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("头")
        assembler.offer("尾")
        XCTAssertEqual(assembler.sealCurrentSegment(), "头尾")
        assembler.offer("新段")
        XCTAssertEqual(assembler.currentFullText, "新段")
        XCTAssertEqual(assembler.fullSegments, ["头尾", "新段"])
    }

    /// 恢复回填往返：落盘的段序装回后，封存段只
    /// 读、新段增量只拼进打开段
    func testRestoreRoundTripKeepsSegmentsApart() {
        var assembler = StreamSegmentAssembler()
        assembler.restore(
            sealed: ["第一段"], current: "第二段半截"
        )
        XCTAssertEqual(assembler.sealedSegments, ["第一段"])
        XCTAssertEqual(assembler.currentFullText, "第二段半截")
        assembler.offer("续")
        XCTAssertEqual(
            assembler.fullSegments, ["第一段", "第二段半截续"]
        )
        XCTAssertEqual(
            assembler.mergedFullText, "第一段\n\n第二段半截续"
        )
    }

    /// 归零整器清空：封存列与当前段同清，新一轮从
    /// 无段起步
    func testResetClearsEverything() {
        var assembler = StreamSegmentAssembler()
        assembler.offer("A")
        assembler.sealCurrentSegment()
        assembler.offer("B")
        assembler.reset()
        XCTAssertTrue(assembler.sealedSegments.isEmpty)
        XCTAssertFalse(assembler.hasCurrentContent)
        XCTAssertEqual(assembler.fullSegments, [])
        XCTAssertEqual(assembler.mergedFullText, "")
        assembler.offer("新轮")
        XCTAssertEqual(assembler.currentFullText, "新轮")
    }
}
