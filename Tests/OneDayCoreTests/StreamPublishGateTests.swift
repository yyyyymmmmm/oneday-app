import OneDayCore
import XCTest

/// 流式累积器（0.5.1 发布闸，§409 步 E 瘦身）：
/// 增量立即入账/fullText 恒精确拼接/空增量无操作/
/// hasContent 生命周期/归零五件钉死。旧发布语义
/// （80ms 窗、64 字阈值、collectDue、flush）的钉
/// 测随步 E 与语义一并退役——累积器与时间无关、
/// 无待发布态，快照概念不存在。
final class StreamPublishGateTests: XCTestCase {

    func testOfferAccumulatesImmediately() {
        var gate = StreamPublishGate()
        gate.offer("你")
        XCTAssertEqual(gate.fullText, "你")
        XCTAssertEqual(gate.text, "你")
        // 后续增量逐个立即入账、无攒压
        gate.offer("好")
        gate.offer("，世界")
        XCTAssertEqual(gate.fullText, "你好，世界")
    }

    func testEmptyDeltaIsNoOp() {
        var gate = StreamPublishGate()
        gate.offer("")
        XCTAssertFalse(gate.hasContent)
        XCTAssertEqual(gate.fullText, "")
        gate.offer("a")
        gate.offer("")
        XCTAssertEqual(gate.fullText, "a")
    }

    func testFullTextIsExactConcatenation() {
        var gate = StreamPublishGate()
        let deltas = ["一", "二三", "", "四", "五六七", "八"]
        var fed = ""
        for delta in deltas {
            gate.offer(delta)
            fed += delta
            // 每一拍后全文恒为已喂分片的精确拼接
            XCTAssertEqual(gate.fullText, fed)
        }
        XCTAssertEqual(gate.fullText, deltas.joined())
    }

    func testHasContentLifecycle() {
        var gate = StreamPublishGate()
        XCTAssertFalse(gate.hasContent)
        gate.offer("")
        XCTAssertFalse(gate.hasContent)
        gate.offer("半截回复")
        XCTAssertTrue(gate.hasContent)
        gate.reset()
        XCTAssertFalse(gate.hasContent)
    }

    func testResetClearsRound() {
        var gate = StreamPublishGate()
        gate.offer("abc")
        gate.reset()
        XCTAssertFalse(gate.hasContent)
        XCTAssertEqual(gate.fullText, "")
        // 归零后新一轮从空起步、互不串字
        gate.offer("z")
        XCTAssertEqual(gate.fullText, "z")
    }
}
