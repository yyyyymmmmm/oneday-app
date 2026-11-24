import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp
import OneDayCore
import OneDayDesign

/// §374.3 帧量测探针（只进测试目标）：步骤 2
/// 探针同口径（控制器单段、best-of-5 min、变更
/// 集计时区外产出）对两构造复测。定因结论
/// （§374.3）：步骤 2 残差的真源是 apply 强
/// 制的整趟布局 pass（逐 item 帧求解、构造无
/// 关），全形态脱钩在 compositional 下不可
/// 达；本探针改钉可达口径——单 section（单
/// 组多 item 形）单行趟低于逐行构造 1/2.5、
/// 绝对上限 7ms@1200、比值有界。实测数入
/// §374.3 量测表
@MainActor
final class ChatSwapStep3ProbeTests: XCTestCase {

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

    private func makeController(
        singleSection: Bool
    ) -> ChatRootViewController {
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
        controller.testSingleSectionOverride = singleSection
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

    private func feed(
        _ controller: ChatRootViewController,
        rows: [ChatNativeRow],
        changeSet: EntryChangeSet
    ) {
        controller.applyChanges(
            rows: rows, changeSet: changeSet,
            layout: layout, topInset: 0,
            bottomMargin: 16,
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

    func testSingleSectionApplyDecoupling() {
        var results: [String: Double] = [:]
        for single in [false, true] {
            let mode = single ? "single" : "section"
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
                let vc = makeController(
                    singleSection: single
                )
                let tracker = ChatFeedChangeTracker()
                feed(
                    vc, rows: base,
                    changeSet: tracker.ingest(rows: base)
                )
                let steadySet = tracker.ingest(rows: base)
                results["steady-\(mode)-\(count)"] =
                    measureMinMicroseconds {
                        feed(
                            vc, rows: base,
                            changeSet: steadySet
                        )
                    }
                // 单行更新（中行修订交替）
                _ = tracker.ingest(rows: rowsV1)
                let singleSet = tracker.ingest(
                    rows: rowsV2
                )
                XCTAssertEqual(
                    singleSet.updated,
                    ["probe-\(mid)"]
                )
                feed(
                    vc, rows: rowsV2, changeSet: singleSet
                )
                var flip = false
                results["update-\(mode)-\(count)"] =
                    measureMinMicroseconds {
                        flip.toggle()
                        feed(
                            vc,
                            rows: flip ? rowsV1 : rowsV2,
                            changeSet: singleSet
                        )
                    }
                // 单行插入/删除（中位插一新行↔删回）
                var extended = base
                var extraRevision =
                    ChatNativeRowRevision()
                extraRevision.addText("extra")
                extended.insert(
                    ChatNativeRow(
                        key: "probe-extra",
                        entryID: nil,
                        revision: extraRevision,
                        height: 80,
                        makeView: {
                            AnyView(EmptyView())
                        }
                    ),
                    at: mid
                )
                let insertSet = tracker.ingest(
                    rows: extended
                )
                XCTAssertEqual(
                    insertSet.inserted, ["probe-extra"]
                )
                let deleteSet = tracker.ingest(rows: base)
                XCTAssertEqual(
                    deleteSet.deleted, ["probe-extra"]
                )
                var inserting = false
                results["insert-\(mode)-\(count)"] =
                    measureMinMicroseconds {
                        inserting.toggle()
                        feed(
                            vc,
                            rows: inserting
                                ? extended : base,
                            changeSet: inserting
                                ? insertSet : deleteSet
                        )
                    }
            }
        }
        print(
            "[swap3-probe] "
                + results.sorted { $0.key < $1.key }
                    .map {
                        "\($0.key)=\(Int($0.value))µs"
                    }
                    .joined(separator: " ")
        )
        let updSingle300 = results["update-single-300"]!
        let updSingle1200 = results["update-single-1200"]!
        let updSection1200 = results["update-section-1200"]!
        let insSingle300 = results["insert-single-300"]!
        let insSingle1200 = results["insert-single-1200"]!
        let steadySingle1200 =
            results["steady-single-1200"]!
        // 改钉口径（§374.3 定因后定版）：全形态
        // 脱钩在 compositional 构造下不可达——
        // apply 强制的整趟布局 pass 由逐 item 帧
        // 求解主导（spike 三变体＋脱窗/隐藏对照
        // 实证、与窗口及我方代码无关）；可达且
        // 已达成的口径＝单组多 item 形把常数压
        // 至逐行构造的 1/2.5 以下＋绝对上限＋比
        // 值有界（防超线性回潮）。实测基线
        // （2026-11-23）：更新 1399/5528µs、插
        // 入 1368/5293µs（300/1200 行）
        XCTAssertLessThan(
            updSingle1200, updSection1200 / 2.5,
            "单 section 1200 行单行更新须低于逐行构造 1/2.5（单 \(Int(updSingle1200))µs vs 逐行 \(Int(updSection1200))µs）"
        )
        XCTAssertLessThan(
            updSingle1200, 7_000,
            "单 section 1200 行单行更新绝对上限 7ms（实测 \(Int(updSingle1200))µs）"
        )
        XCTAssertLessThan(
            updSingle1200,
            updSingle300 * 5 + 1_000,
            "单 section 单行更新比值须有界（300:\(Int(updSingle300))µs 1200:\(Int(updSingle1200))µs）"
        )
        XCTAssertLessThan(
            insSingle1200, 7_000,
            "单 section 1200 行单行插入绝对上限 7ms（实测 \(Int(insSingle1200))µs）"
        )
        XCTAssertLessThan(
            insSingle1200,
            insSingle300 * 5 + 1_000,
            "单 section 单行插入比值须有界（300:\(Int(insSingle300))µs 1200:\(Int(insSingle1200))µs）"
        )
        // 稳态性质沿步骤 2 口径不退化
        XCTAssertLessThan(
            steadySingle1200, 1_000,
            "单 section 稳态趟应趋近于零（实测 \(Int(steadySingle1200))µs）"
        )
    }
}

