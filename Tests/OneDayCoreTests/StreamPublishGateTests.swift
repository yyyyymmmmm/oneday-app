import OneDayCore
import XCTest

/// 流式发布合并闸（0.5.1，§32）：窗口合并/阈值触发/
/// 收尾 flush 精确/取消 flush/空增量不发布五件钉死。
/// 时刻为注入的单调时钟字面值（秒），与生产口径同源
/// （80ms 窗、64 字阈值见 StreamPublishGate 常量）。
final class StreamPublishGateTests: XCTestCase {

    func testFirstDeltaPublishesImmediately() {
        var gate = StreamPublishGate()
        XCTAssertEqual(gate.offer("你", at: 10.0), "你")
        XCTAssertEqual(gate.publishedText, "你")
        XCTAssertFalse(gate.hasPending)
    }

    func testWindowMerging() {
        var gate = StreamPublishGate()
        XCTAssertEqual(gate.offer("a", at: 0), "a")
        // 窗内（<80ms）的后续增量只攒不发
        XCTAssertNil(gate.offer("b", at: 0.03))
        XCTAssertNil(gate.offer("c", at: 0.06))
        XCTAssertEqual(gate.publishedText, "a")
        XCTAssertEqual(gate.pendingText, "bc")
        // 满窗后的下一个增量带着积压一次发布
        XCTAssertEqual(gate.offer("d", at: 0.09), "abcd")
        XCTAssertFalse(gate.hasPending)
    }

    func testThresholdTriggersBeforeWindow() {
        var gate = StreamPublishGate()
        XCTAssertEqual(gate.offer("x", at: 0), "x")
        let bulk = String(repeating: "y", count: 40)
        XCTAssertNil(gate.offer(bulk, at: 0.01))
        // 累计待发布达 64 字阈值：未满窗也立即发布
        XCTAssertEqual(gate.offer(bulk, at: 0.02), "x" + bulk + bulk)
    }

    func testCollectDuePublishesTailAfterWindow() {
        var gate = StreamPublishGate()
        XCTAssertEqual(gate.offer("a", at: 0), "a")
        XCTAssertNil(gate.offer("b", at: 0.02))
        // 未满窗：巡查不发
        XCTAssertNil(gate.collectDue(at: 0.05))
        // 满窗：巡查把尾巴增量推出，不必等新增量
        XCTAssertEqual(gate.collectDue(at: 0.09), "ab")
        // 无待发布时巡查恒 nil
        XCTAssertNil(gate.collectDue(at: 1.0))
    }

    func testFlushIsExactAndIdempotent() {
        var gate = StreamPublishGate()
        gate.offer("Hello", at: 0)
        gate.offer(", ", at: 0.01)
        gate.offer("world", at: 0.02)
        // 收尾 flush：残余精确拼上，不多不少不重复
        XCTAssertEqual(gate.flush(at: 0.03), "Hello, world")
        XCTAssertEqual(gate.fullText, "Hello, world")
        // 再 flush 无残余：不重复发布
        XCTAssertNil(gate.flush(at: 0.04))
    }

    func testCancelFlushKeepsPartialExactly() {
        var gate = StreamPublishGate()
        gate.offer("半截", at: 0)
        gate.offer("回复", at: 0.01)
        // 用户取消时的收尾 flush＝已到增量的精确全文
        XCTAssertEqual(gate.flush(at: 0.02), "半截回复")
    }

    func testEmptyDeltaNeverPublishes() {
        var gate = StreamPublishGate()
        XCTAssertNil(gate.offer("", at: 0))
        XCTAssertFalse(gate.hasContent)
        XCTAssertEqual(gate.offer("a", at: 0.01), "a")
        XCTAssertNil(gate.offer("", at: 0.02))
        XCTAssertEqual(gate.fullText, "a")
    }

    func testFullTextIsExactConcatenation() {
        var gate = StreamPublishGate()
        let deltas = ["一", "二三", "", "四", "五六七", "八"]
        var now = 0.0
        for delta in deltas {
            gate.offer(delta, at: now)
            now += 0.01
        }
        XCTAssertEqual(gate.fullText, deltas.joined())
    }

    func testResetClearsRound() {
        var gate = StreamPublishGate()
        gate.offer("abc", at: 0)
        gate.reset()
        XCTAssertFalse(gate.hasContent)
        XCTAssertEqual(gate.fullText, "")
        // 归零后首增量恢复立即发布
        XCTAssertEqual(gate.offer("z", at: 100), "z")
    }
}
