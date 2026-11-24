import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §422 包 2（resolve 纯读化）取证夹具——对崩②
/// （0.50.102，204455.ips：ChatView.nativeRows 在
/// body 求值期调 Desk.resolve，命中分支当场写
/// jobsByRowKey[rowKey] = nil，Dictionary.subscript
/// .setter 内同步析构工单、闭包析构链 swift_release
/// 撞已释放内存 @0x18）。
///
/// 修法口径（施工图包 2）：resolve 求值期零字典写
/// 入、零工单析构——命中清账（jobsByRowKey/memo-
/// KeyByRowKey 置 nil）与 lastKnownByRow 回写一律
/// 登记待落写，由 flushCollected 开头（趟末收尾
/// 段）在求值期之外统一执行；清账按命中 memoKey
/// 守卫，不误清同行后收集的新修订工单；lastKnown
/// 沿用旧值一趟为图 §六已认风险（高度-only 修正
/// 路径不变）。
///
/// 可观察差（先红依据，全部经 Desk 公开读口）：
/// - 命中后、flush 前：measureNow 仍能在留账工单
///   ＋缓存命中下回确定高（旧码命中即清账→回 nil）
/// - 命中后、flush 前：异键未命中读 lastKnown 仍
///   回兜底（旧码已同步回写→回命中高）；flush 后
///   回命中高（落写已执行、终态与旧码一致）
@MainActor
final class RowMeasurePureRead422Tests: XCTestCase {

    private func job(
        memoKey: String, rowKey: String,
        height: CGFloat
    ) -> ChatNativeRowMeasureJob {
        ChatNativeRowMeasureJob(
            memoKey: memoKey, rowKey: rowKey
        ) { height }
    }

    /// 先红主证一：命中清账后移——flush 前留账工单
    /// 仍在，measureNow 经工单＋缓存命中回确定高；
    /// 旧码 resolve 命中即清双账，measureNow 回 nil
    func testHitDefersLedgerClearingUntilFlush() {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "pure422-clear-\(suffix)"
        let rowKey = "pure422-clear-row-\(suffix)"
        desk.collect(
            job(memoKey: memoKey, rowKey: rowKey, height: 88)
        )
        // 模拟工单已由别路完成、缓存已落而留账未清
        ChatNativeRowHeightComposer.storeRowHeight(
            88, forKey: memoKey
        )
        let hit = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(hit.height, 88)
        XCTAssertTrue(hit.isExact)
        XCTAssertFalse(hit.needsJob)
        XCTAssertEqual(
            desk.measureNow(rowKey: rowKey), 88,
            "命中清账须后移至趟末落写：flush 前 measureNow"
                + " 应仍回缓存确定高；旧码命中即清账此处回 nil"
        )
    }

    /// 先红主证二：lastKnown 回写后移——flush 前异
    /// 键未命中仍回兜底（回写未落），flush 后回命
    /// 中高（落写已执行、终态与旧码一致）
    func testHitDefersLastKnownWritebackUntilFlush() {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "pure422-known-\(suffix)"
        let otherKey = "pure422-known-other-\(suffix)"
        let rowKey = "pure422-known-row-\(suffix)"
        ChatNativeRowHeightComposer.storeRowHeight(
            92, forKey: memoKey
        )
        let hit = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(hit.height, 92)
        XCTAssertTrue(hit.isExact)
        let beforeFlush = desk.resolve(
            memoKey: otherKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(
            beforeFlush.height, 120,
            "lastKnown 回写须后移：flush 前异键未命中应回"
                + "兜底；旧码命中即同步回写此处回 92"
        )
        XCTAssertTrue(beforeFlush.needsJob)
        desk.flushCollected()
        let afterFlush = desk.resolve(
            memoKey: otherKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(
            afterFlush.height, 92,
            "flush 落写后 lastKnown 须为命中高（终态与旧码一致）"
        )
    }

    /// 终态 pin：flush 落写后双留账清——measureNow
    /// 无工单无留账键回 nil（与旧码终态一致，只移
    /// 时机不移终态）
    func testSettlementAtFlushClearsBothLedgers() {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "pure422-settle-\(suffix)"
        let rowKey = "pure422-settle-row-\(suffix)"
        desk.collect(
            job(memoKey: memoKey, rowKey: rowKey, height: 94)
        )
        ChatNativeRowHeightComposer.storeRowHeight(
            94, forKey: memoKey
        )
        let hit = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(hit.height, 94)
        desk.flushCollected()
        XCTAssertNil(
            desk.measureNow(rowKey: rowKey),
            "flush 落写后留账双清：measureNow 应回 nil"
        )
    }

    /// 守卫 pin：命中落写按 memoKey 守卫——同行其后
    /// 收集的新修订工单（异键）不被旧命中的落写误
    /// 清，flush 后仍可经 measureNow 量出新高
    /// （§430 时序改形：单执行者纪律下 flush 后队
    /// 列可能已认领新单执行中，measureNow 单次调
    /// 用可合法回 nil——断言本体（新单不被误清、
    /// 终态经 measureNow 得 66）不放松，只改单次
    /// 同步调用为轮询收敛）
    func testSettlementDoesNotClearNewerJobForSameRow() async {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let oldKey = "pure422-guard-old-\(suffix)"
        let newKey = "pure422-guard-new-\(suffix)"
        let rowKey = "pure422-guard-row-\(suffix)"
        ChatNativeRowHeightComposer.storeRowHeight(
            55, forKey: oldKey
        )
        desk.collect(
            job(memoKey: oldKey, rowKey: rowKey, height: 55)
        )
        let hit = desk.resolve(
            memoKey: oldKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(hit.height, 55)
        // 同趟内同行修订变更：新键工单收集在后
        desk.collect(
            job(memoKey: newKey, rowKey: rowKey, height: 66)
        )
        desk.flushCollected()
        var measured: CGFloat?
        let deadline = Date().addingTimeInterval(5)
        while measured == nil, Date() < deadline {
            measured = desk.measureNow(rowKey: rowKey)
            if measured == nil {
                try? await Task.sleep(
                    nanoseconds: 20_000_000
                )
            }
        }
        XCTAssertEqual(
            measured, 66,
            "落写清账须按命中键守卫：新修订工单不许被旧命中误清"
        )
    }

    /// 同趟 resolve 序（图 §六守例）：未命中→收集
    /// →不重复报 needsJob；缓存落后趟内反复命中稳
    /// 定；flush 后仍命中——后移清账不许造成同趟
    /// 重复组装或命中丢失
    func testSamePassResolveOrderNoDuplicateAssembly() {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let memoKey = "pure422-order-\(suffix)"
        let rowKey = "pure422-order-row-\(suffix)"
        let first = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(first.height, 120)
        XCTAssertTrue(first.needsJob)
        desk.collect(
            job(memoKey: memoKey, rowKey: rowKey, height: 70)
        )
        let second = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertFalse(
            second.needsJob, "已收集的键不许重复报 needsJob"
        )
        ChatNativeRowHeightComposer.storeRowHeight(
            70, forKey: memoKey
        )
        let third = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(third.height, 70)
        XCTAssertTrue(third.isExact)
        let fourth = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(
            fourth.height, 70,
            "趟内反复命中须稳定（落写后移不丢命中）"
        )
        desk.flushCollected()
        let fifth = desk.resolve(
            memoKey: memoKey, rowKey: rowKey, fallback: 120
        )
        XCTAssertEqual(fifth.height, 70)
        XCTAssertFalse(fifth.needsJob)
    }

    /// 批量命中压测（图 §五夹具 2 形态）：多轮、
    /// 每轮 48 行，在飞（先 flush 投递）与已收集
    /// （未投递）两类工单交错，缓存全落后按
    /// nativeRows 序高频走命中路径（旧码在此批量
    /// 同步析构工单），趟末 flush 落写后逐行验终
    /// 态（lastKnown 落定＋双账清）。ASan/TSan 轮
    /// 以本例为载体取证
    func testBatchHitPassAcrossInFlightAndCollected() {
        let desk = ChatNativeRowMeasureDesk()
        let suffix = UUID().uuidString
        let rowCount = 48
        for round in 0..<3 {
            var keys: [(memo: String, row: String, height: CGFloat)] = []
            for index in 0..<rowCount {
                let memo =
                    "pure422-batch-r\(round)-\(index)-\(suffix)"
                let row =
                    "pure422-batch-row-r\(round)-\(index)-\(suffix)"
                let height = CGFloat(100 + index)
                keys.append((memo, row, height))
                desk.collect(
                    job(memoKey: memo, rowKey: row, height: height)
                )
                if index == rowCount / 2 - 1 {
                    // 前半行先投递成在飞类，后半行留已收集类
                    desk.flushCollected()
                }
            }
            // 模拟两类工单均已由别路完成、缓存全落
            for entry in keys {
                ChatNativeRowHeightComposer.storeRowHeight(
                    entry.height, forKey: entry.memo
                )
            }
            // nativeRows 序高频命中（旧码批量同步析构点）
            for entry in keys {
                let hit = desk.resolve(
                    memoKey: entry.memo, rowKey: entry.row,
                    fallback: 120
                )
                XCTAssertEqual(
                    hit.height, entry.height,
                    "第 \(round) 轮 \(entry.row) 命中高须逐值"
                )
                XCTAssertTrue(hit.isExact)
            }
            desk.flushCollected()
            for entry in keys {
                XCTAssertNil(
                    desk.measureNow(rowKey: entry.row),
                    "第 \(round) 轮 \(entry.row)：落写后双账须清"
                )
                let known = desk.resolve(
                    memoKey:
                        "pure422-batch-probe-r\(round)-\(suffix)",
                    rowKey: entry.row, fallback: 120
                )
                XCTAssertEqual(
                    known.height, entry.height,
                    "第 \(round) 轮 \(entry.row)：落写后 lastKnown 须落定"
                )
            }
        }
    }
}
