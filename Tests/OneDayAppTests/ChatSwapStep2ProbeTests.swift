import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.2 帧量测探针（只进测试目标）：控制器侧
/// apply 路径同口径对账——旧路 applyNow（全量
/// 对账）vs 新路 applyChanges（变更集增量），同
/// 合成会话、best-of-5（min）。计时区只含控制
/// 器落写本体（行构建与变更集产出在计时区外备
/// 好——与 S3「无变化重喂 apply 下限」的 apply
/// 单段口径同义）。验收门②两性质在本步的实测
/// 结论（2026-11-23 ProbePhone 实测，见 §374.2
/// 量测表）：②无变更重喂——新路 2µs（两档同
/// 值）vs 旧路 332/1,332µs 全量成立；①单行变
/// 更——对账片已脱钩（旧路稳态成本随行数
/// 332→1,332µs、新路恒 ~0），但单行趟总成本
/// 被快照 apply 本体主导（~12.7µs/行、单插/
/// 单删/单重构同价、两路同价、隐藏窗口不变）
/// ——现行「每行一 section」的 diffable apply
/// 成本、正是步骤 3（单 section 收敛）的靶子；
/// 本步断言只钉本步所辖：对账片脱钩＋单行新路
/// 不劣于旧路，apply 残差待步骤 3 后改钉全形
/// 态。S3 基线（rel-05093 树整趟口径：稳态
/// 8,458µs／单行 8,821µs／全量 33,178µs）为
/// 参照系——本探针是控制器单段口径、绝对值小
/// 于整趟，对账看相对量级与脱钩性
@MainActor
final class ChatSwapStep2ProbeTests: XCTestCase {

    private let layout = ChatNativeLayout(
        horizontalPadding: OneDayMetrics.pageGutter,
        topPadding: OneDayMetrics.spacingM,
        bottomPadding: 8,
        rowSpacing: OneDayMetrics.spacingL,
        arrowTrailing: OneDayMetrics.spacingM,
        arrowGapAboveComposer: 8,
        arrowSize: OneDayMetrics.minTapTarget
    )
    private var windows: [UIWindow] = []

    override func tearDown() {
        for window in windows { window.isHidden = true }
        windows = []
        super.tearDown()
    }

    private func makeController() -> ChatRootViewController {
        let window = UIWindow(
            frame: CGRect(x: 0, y: 0, width: 390, height: 844)
        )
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        windows.append(window)
        let handle = ChatNativeListHandle()
        let controller = ChatRootViewController()
        controller.handle = handle
        controller.callbacks = ChatNativeListCallbacks(
            onScrollGeometry: {},
            onTopVisibleEntry: { _ in },
            onBlankTap: {}
        )
        handle.controller = controller
        root.addChild(controller)
        controller.view.frame = root.view.bounds
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
        root.view.layoutIfNeeded()
        return controller
    }

    private func makeRows(
        count: Int, changedIndex: Int? = nil,
        changedVersion: Int = 0
    ) -> [ChatNativeRow] {
        (0..<count).map { index in
            var revision = ChatNativeRowRevision()
            revision.addText("row-\(index)")
            if index == changedIndex {
                revision.addText("v\(changedVersion)")
            }
            return ChatNativeRow(
                key: "probe-\(index)",
                entryID: nil,
                revision: revision,
                height: 80,
                makeView: { AnyView(EmptyView()) }
            )
        }
    }

    private func feedOld(
        _ controller: ChatRootViewController,
        rows: [ChatNativeRow]
    ) {
        controller.apply(
            rows: rows, layout: layout,
            topInset: 0, bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    private func feedNew(
        _ controller: ChatRootViewController,
        rows: [ChatNativeRow],
        changeSet: EntryChangeSet
    ) {
        controller.applyChanges(
            rows: rows, changeSet: changeSet,
            layout: layout,
            topInset: 0, bottomMargin: 16,
            composerView: AnyView(Color.clear),
            arrowView: AnyView(Color.clear)
        )
    }

    /// best-of-5（min，µs）：预热 2 次不计
    private func measureMinMicroseconds(
        warmup: Int = 2, reps: Int = 5,
        _ body: () -> Void
    ) -> Double {
        for _ in 0..<warmup { body() }
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<reps {
            let start = CFAbsoluteTimeGetCurrent()
            body()
            best = min(
                best,
                (CFAbsoluteTimeGetCurrent() - start)
                    * 1_000_000
            )
        }
        return best
    }

    func testApplyPathCostDecoupling() {
        var results: [String: Double] = [:]
        for count in [300, 1200] {
            let mid = count / 2
            let base = makeRows(count: count)
            let rowsV1 = makeRows(
                count: count, changedIndex: mid,
                changedVersion: 1
            )
            let rowsV2 = makeRows(
                count: count, changedIndex: mid,
                changedVersion: 2
            )
            // 旧路（全量对账）：冷开→稳态→单行交替
            let oldVC = makeController()
            feedOld(oldVC, rows: base)
            results["steady-old-\(count)"] =
                measureMinMicroseconds {
                    feedOld(oldVC, rows: base)
                }
            var oldFlip = false
            results["single-old-\(count)"] =
                measureMinMicroseconds {
                    oldFlip.toggle()
                    feedOld(
                        oldVC,
                        rows: oldFlip ? rowsV1 : rowsV2
                    )
                }
            // 新路（变更集增量）：变更集计时区外产
            // 出、只量控制器落写本体
            let newVC = makeController()
            let tracker = ChatFeedChangeTracker()
            feedNew(
                newVC, rows: base,
                changeSet: tracker.ingest(rows: base)
            )
            let steadySet = tracker.ingest(rows: base)
            XCTAssertTrue(
                steadySet.isEmpty
                    && steadySet.heightChanged.isEmpty
            )
            results["steady-new-\(count)"] =
                measureMinMicroseconds {
                    feedNew(
                        newVC, rows: base,
                        changeSet: steadySet
                    )
                }
            _ = tracker.ingest(rows: rowsV1)
            let singleSet = tracker.ingest(rows: rowsV2)
            XCTAssertEqual(
                singleSet.updated, ["probe-\(mid)"]
            )
            feedNew(
                newVC, rows: rowsV2, changeSet: singleSet
            )
            var newFlip = false
            results["single-new-\(count)"] =
                measureMinMicroseconds {
                    newFlip.toggle()
                    feedNew(
                        newVC,
                        rows: newFlip ? rowsV1 : rowsV2,
                        changeSet: singleSet
                    )
                }
        }
        print(
            "[swap2-probe] "
                + results.sorted { $0.key < $1.key }
                    .map {
                        "\($0.key)=\(Int($0.value))µs"
                    }
                    .joined(separator: " ")
        )
        let steadyNew300 = results["steady-new-300"]!
        let steadyNew1200 = results["steady-new-1200"]!
        let steadyOld300 = results["steady-old-300"]!
        let steadyOld1200 = results["steady-old-1200"]!
        let singleNew300 = results["single-new-300"]!
        let singleNew1200 = results["single-new-1200"]!
        let singleOld300 = results["single-old-300"]!
        let singleOld1200 = results["single-old-1200"]!
        // 性质②：无变更重喂趋近于零（<1ms 留足噪
        // 声余量；旧路同口径为整表对账量级）
        XCTAssertLessThan(
            steadyNew1200, 1_000,
            "新路稳态趟应趋近于零（实测 \(Int(steadyNew1200))µs）"
        )
        XCTAssertLessThan(
            steadyNew1200, steadyOld1200 / 4,
            "新路稳态应远低于旧路全量对账"
        )
        // 性质①（本步所辖的对账片）：旧路稳态成本
        // 随行数涨（300→1200 约 4 倍）、新路两档
        // 恒趋近于零——对账与行数脱钩
        XCTAssertGreaterThan(
            steadyOld1200, steadyOld300 * 2,
            "旧路对账成本应随行数涨（300:\(Int(steadyOld300))µs 1200:\(Int(steadyOld1200))µs）"
        )
        XCTAssertLessThan(
            steadyNew300, 1_000,
            "新路 300 行稳态亦应趋近于零（实测 \(Int(steadyNew300))µs）"
        )
        // 单行变更：新路不劣于旧路（两档）；总成
        // 本残差为多 section 快照 apply 本体（步
        // 骤 3 靶子，见头注），本步不钉绝对脱钩
        XCTAssertLessThan(
            singleNew300, singleOld300 * 1.25,
            "新路单行（300）不劣于旧路（新 \(Int(singleNew300))µs 旧 \(Int(singleOld300))µs）"
        )
        XCTAssertLessThan(
            singleNew1200, singleOld1200 * 1.25,
            "新路单行（1200）不劣于旧路（新 \(Int(singleNew1200))µs 旧 \(Int(singleOld1200))µs）"
        )
    }
}
