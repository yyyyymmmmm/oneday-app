import OneDayCore
import XCTest

/// 已决记录单源合并（§259）：近窗在前、同 id 近窗
/// 优先、宽窗补位、保序不重排——逐项钉死。此前同
/// 一本账在三处消费点各自现拼（含两处 View 层），
/// 合成规则自此只此一处有测试护栏
final class DecisionRecordHistoryTests: XCTestCase {
    private func record(
        _ id: String, summary: String? = nil
    ) -> WriteGateDecisionRecord {
        WriteGateDecisionRecord(
            id: id, subsystem: .memory, action: "append",
            summary: summary ?? id, origin: "test",
            decision: "approved", decidedAt: nil
        )
    }

    /// 宽窗未就绪（nil）：全集＝近窗原样
    func testMergeWideNotReadyReturnsRecentAsIs() {
        let recent = [record("a"), record("b")]
        XCTAssertEqual(
            DecisionRecordHistory.merge(recent: recent, wide: nil),
            recent
        )
    }

    /// 宽窗补近窗没有的：结果＝近窗全量＋宽窗独有，
    /// 顺序＝近窗序在前、宽窗独有保宽窗序
    func testMergeAppendsWideOnlyRecordsInOrder() {
        let recent = [record("b"), record("a")]
        let wide = [record("a"), record("c"), record("b"), record("d")]
        XCTAssertEqual(
            DecisionRecordHistory.merge(recent: recent, wide: wide)
                .map(\.id),
            ["b", "a", "c", "d"]
        )
    }

    /// 同 id 两窗都有：只留一份且以近窗为准（近窗拉
    /// 取更新）——旧三处现拼是直接相加留双份，查账靠
    /// first 命中近窗份；合成去重后查账结果不变
    func testMergeDuplicateIDKeepsRecentCopyOnly() {
        let recent = [record("a", summary: "近窗版")]
        let wide = [record("a", summary: "宽窗版")]
        let merged = DecisionRecordHistory.merge(
            recent: recent, wide: wide)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.summary, "近窗版")
    }

    /// 记录数对账基线：合成条数＝近窗数＋宽窗独有数，
    /// 恒不大于旧现拼（近窗＋宽窗全量）、恒不小于任
    /// 一单窗——只减重复、不丢记录
    func testMergeCountIsUnionCardinality() {
        let recent = [record("a"), record("b"), record("c")]
        let wide = [record("b"), record("c"), record("d"),
                    record("e"), record("f")]
        let merged = DecisionRecordHistory.merge(
            recent: recent, wide: wide)
        XCTAssertEqual(merged.count, 6)
        XCTAssertEqual(Set(merged.map(\.id)),
                       ["a", "b", "c", "d", "e", "f"])
    }

    /// 双空与近窗空：宽窗独任时全集＝宽窗原样
    func testMergeEmptyRecentReturnsWide() {
        let wide = [record("x"), record("y")]
        XCTAssertEqual(
            DecisionRecordHistory.merge(recent: [], wide: wide),
            wide
        )
        XCTAssertEqual(
            DecisionRecordHistory.merge(recent: [], wide: nil), []
        )
    }
}
