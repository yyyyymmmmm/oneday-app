import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §419 包 1（量测收口）取证夹具——对崩①（0.50.99
/// 153224.ips：后台工单经 segmentHeight 代码段／
/// tableCellTextHeight 直调 referenceHeight，在后
/// 台线程变异全局共享 UITextView 量测台，TextKit 2
/// 枚举期异常 abort）。
///
/// 形态：合成器取量测台形态（§331 第二 init：无活
/// 读源、facets 唯一输入），与生产量测工单同形。
/// 条目集恒含代码块＋表格（两处直调的必经路）。
///
/// 备忘口径（决定夹具形态）：合成器文本备忘为静
/// 态共享 NSCache、同文本第二路必命中不真量——故
/// 每路用等长 token 变体（仅代码块内标识符不同、
/// 等距字体等长即等宽、版式逐值同高），备忘键互
/// 异而高度可比；量测台备忘以串实例身份为键、合
/// 成器逐算新建实例恒未命中，变异段每算必达。
///
/// 旧码期望（先红）：后台路直调落 measuredSize 变
/// 异段——debug 断言哨（§419，量测台只许主线程变
/// 异）触发 abort，或 TK2 枚举期异常 abort，进程
/// 级红。收口后期望：后台路全走 ChatNativeText-
/// Measure 分发（后台落量测池），断言永不触发、
/// 主/后台两路同值（±1pt），全绿。
final class RowMeasureConfinement419Tests: XCTestCase {

    /// 合成器装箱：核心本体按 §331 为线程无关纯量
    /// 测（备忘为 NSCache＋锁盒计数），装箱只为过
    /// 测试侧的并发捕获检查（与生产 LayoutAttri-
    /// butedBox 同式）
    private final class ComposerBox: @unchecked Sendable {
        let composer: ChatNativeRowHeightComposer
        init(_ composer: ChatNativeRowHeightComposer) {
            self.composer = composer
        }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: CGFloat] = [:]
        func store(path: String, round: Int, item: Int, height: CGFloat) {
            lock.lock()
            values["\(path)-\(round)-\(item)"] = height
            lock.unlock()
        }
        func get(path: String, round: Int, item: Int) -> CGFloat? {
            lock.lock()
            defer { lock.unlock() }
            return values["\(path)-\(round)-\(item)"]
        }
    }

    private func makeComposer() -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: 402,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72,
            facets: ChatNativeRowFacets()
        )
    }

    /// 含代码块＋表格的条目（两处直调必经）；token
    /// 只入代码块标识符（等长变体版式同高）、round/
    /// item 入文保证逐轮逐条内容互异
    private static func stressText(
        round: Int, item: Int, token: String
    ) -> String {
        """
        第 \(round) 轮第 \(item) 条正文，散文段撑量测路径并保证内容互异 \(round)-\(item)。

        ```swift
        let value_\(token) = compute(value: \(round * 100 + item))
        print(value_\(token))
        // 代码行 \(round)-\(item)：代码段走 segmentHeight 代码分支
        ```

        | 列甲 \(round) | 列乙 \(item) | 列丙 |
        | --- | --- | --- |
        | 单元格 \(round)-\(item)-1 | 较长的单元格文本内容 \(round) 号 | 值 \(item) |
        | 第二行 \(item) | 单元格 \(round) 号文本 | 尾格 \(round)-\(item) |
        """
    }

    /// 直测：单条后台量测与主线程量测同值（等长
    /// token 变体避静态备忘）。旧码下后台调用直落
    /// 量测台变异段（哨红/abort）
    func testBackgroundMeasureMatchesMainForCodeAndTable() {
        let mainBox = ComposerBox(makeComposer())
        let backgroundBox = ComposerBox(makeComposer())
        let mainHeight = mainBox.composer.markdownHeight(
            Self.stressText(round: 900, item: 1, token: "mm")
        )
        XCTAssertGreaterThan(mainHeight, 0)
        let done = DispatchSemaphore(value: 0)
        let backgroundHeight = ResultBox()
        DispatchQueue.global(qos: .userInitiated).async {
            let height = backgroundBox.composer.markdownHeight(
                Self.stressText(round: 900, item: 1, token: "bg")
            )
            backgroundHeight.store(
                path: "bg", round: 0, item: 0, height: height
            )
            done.signal()
        }
        XCTAssertEqual(
            done.wait(timeout: .now() + 60), .success,
            "后台量测未在限时内完成"
        )
        let measured = backgroundHeight.get(path: "bg", round: 0, item: 0)
        XCTAssertNotNil(measured)
        if let measured {
            XCTAssertEqual(
                measured, mainHeight, accuracy: 1.0,
                "后台量测与主线程量测分家：bg \(measured) vs main \(mainHeight)"
            )
        }
    }

    /// 压测：主线程同步量测全表＋两条后台队列整表
    /// 量测并发交叠多轮（模拟量测台预排版与主线程
    /// 同步兜底同刻在席）；每路 token 变体独立、各
    /// 路真量，收口后两路逐条同值
    func testConcurrentMeasureStressMainVersusBackground() {
        let mainBox = ComposerBox(makeComposer())
        let workerBoxes = [
            ComposerBox(makeComposer()),
            ComposerBox(makeComposer()),
        ]
        let workerTokens = ["b0", "b1"]
        let results = ResultBox()
        let rounds = 6
        let items = 24
        let group = DispatchGroup()
        for (worker, box) in workerBoxes.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for round in 0..<rounds {
                    for item in 0..<items {
                        let height = box.composer.markdownHeight(
                            Self.stressText(
                                round: round, item: item,
                                token: workerTokens[worker]
                            )
                        )
                        if worker == 0 {
                            results.store(
                                path: "bg", round: round, item: item,
                                height: height
                            )
                        }
                    }
                }
                group.leave()
            }
        }
        for round in 0..<rounds {
            for item in 0..<items {
                let height = mainBox.composer.markdownHeight(
                    Self.stressText(round: round, item: item, token: "mm")
                )
                results.store(
                    path: "main", round: round, item: item,
                    height: height
                )
            }
        }
        XCTAssertEqual(
            group.wait(timeout: .now() + 180), .success,
            "后台量测未在限时内完成"
        )
        var mismatches: [String] = []
        for round in 0..<rounds {
            for item in 0..<items {
                guard let main = results.get(
                    path: "main", round: round, item: item
                ), let background = results.get(
                    path: "bg", round: round, item: item
                ) else {
                    mismatches.append("缺值 \(round)-\(item)")
                    continue
                }
                if abs(main - background) > 1.0 {
                    mismatches.append(
                        "\(round)-\(item)：main \(main) vs bg \(background)"
                    )
                }
            }
        }
        XCTAssertTrue(
            mismatches.isEmpty,
            "主/后台量测分家：\(mismatches.prefix(5))"
        )
    }
}
