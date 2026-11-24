import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// D4（§349）来源条行高对账：来源条进气泡高度合
/// 成路径后，合成器定价（sourceStripHeight／条
/// 目级增量）与生产视图本体（MessageSource-
/// StripView）的真实拟合高必须逐值相等（±1pt，
/// 与 §329 拟合纪律同口径）——条收/展两态、条目
/// 级增量两态、无来源零增量，共五钉
@MainActor
final class MessageSourceStripFittingTests: XCTestCase {

    private let screenW: CGFloat = 402
    private var contentW: CGFloat { screenW - 40 }

    private func makeComposer(
        ledger: ChatRowStateLedger
    ) -> ChatNativeRowHeightComposer {
        ChatNativeRowHeightComposer(
            screenWidth: screenW,
            horizontalPadding: OneDayMetrics.pageGutter,
            sizeCategory: .large,
            boldText: false,
            displayScale: 3,
            ledger: ledger,
            hubStore: AppState().sharedHubStore(),
            agentDisplayName: "Hermes",
            emptyStateAvatarSize: 72
        )
    }

    private func fit(_ view: AnyView, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(
            in: CGSize(
                width: width,
                height: .greatestFiniteMagnitude
            )
        ).height
    }

    private let sampleSources = [
        MessageSource(
            title: "SwiftUI 列表性能指南",
            url: "https://developer.apple.com/documentation/swiftui/list"
        ),
        MessageSource(
            title: "一篇很长的标题用来验证单行截断时行高仍是一行价的来源标题",
            url: "https://example.com/articles/2026/11/a-very-long-path"
        ),
        MessageSource(
            title: "Example Domain",
            url: "https://www.example.org/"
        ),
    ]

    private func stripView(
        entry: ChatEntry, ledger: ChatRowStateLedger
    ) -> AnyView {
        AnyView(
            MessageSourceStripView(
                sources: sampleSources,
                expansionKey: ChatRowStateKeys.sourcesEntry(
                    entry.id
                ),
                ledger: ledger
            )
            .environment(\.dynamicTypeSize, .large)
        )
    }

    /// 条本体两态：拟合高＝合成器 sourceStrip-
    /// Height（同账本同展开态）
    func testStripHeightsMatchComposerBothStates() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let entry = ChatEntry(
            role: "assistant", content: "定稿回答。", thread: nil
        )
        let snapshot = ChatEntryHeightSnapshot(
            entry, sources: sampleSources
        )

        let collapsedFit = fit(
            stripView(entry: entry, ledger: ledger),
            width: contentW
        )
        XCTAssertEqual(
            collapsedFit, composer.sourceStripHeight(snapshot),
            accuracy: 1.0,
            "收起态：拟合 \(collapsedFit) 与合成 "
                + "\(composer.sourceStripHeight(snapshot)) 须相等"
        )
        XCTAssertEqual(
            composer.sourceStripHeight(snapshot),
            OneDayMetrics.minTapTarget, accuracy: 0.5,
            "收起态条高恒 minTapTarget"
        )

        ledger.setExpansion(
            true, for: ChatRowStateKeys.sourcesEntry(entry.id)
        )
        let expandedFit = fit(
            stripView(entry: entry, ledger: ledger),
            width: contentW
        )
        XCTAssertEqual(
            expandedFit, composer.sourceStripHeight(snapshot),
            accuracy: 1.0,
            "展开态：拟合 \(expandedFit) 与合成 "
                + "\(composer.sourceStripHeight(snapshot)) 须相等"
        )
        XCTAssertGreaterThan(
            expandedFit, collapsedFit,
            "展开态必须高于收起态（列表段在价内）"
        )
    }

    /// 条目级增量：同条目有/无来源的行高差＝
    /// spacingS＋条高（收/展两态）；无来源恒与
    /// 旧口径同值由差分构造保证
    func testEntryHeightDeltaEqualsStripSlot() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let entry = ChatEntry(
            role: "assistant",
            content: "这是一段带来源的定稿回答。",
            thread: nil
        )
        let snapshot = ChatEntryHeightSnapshot(
            entry, sources: sampleSources
        )

        let base = composer.entryHeight(entry, dividerText: nil)
        let withSources = composer.entryHeight(
            entry, dividerText: nil, sources: sampleSources
        )
        XCTAssertEqual(
            withSources - base,
            OneDayMetrics.spacingS
                + composer.sourceStripHeight(snapshot),
            accuracy: 0.5,
            "收起态条目增量须恰为槽价（spacingS＋条高）"
        )

        ledger.setExpansion(
            true, for: ChatRowStateKeys.sourcesEntry(entry.id)
        )
        let expanded = composer.entryHeight(
            entry, dividerText: nil, sources: sampleSources
        )
        XCTAssertEqual(
            expanded - base,
            OneDayMetrics.spacingS
                + composer.sourceStripHeight(snapshot),
            accuracy: 0.5,
            "展开态条目增量须恰为槽价（spacingS＋展开条高）"
        )
        XCTAssertGreaterThan(expanded, withSources)
    }

    /// 用户条目不承接来源槽：聚合只挂定稿助手条
    /// 目，合成器用户支不读 sources（传了也不加价）
    func testUserEntryIgnoresSources() {
        let ledger = ChatRowStateLedger()
        let composer = makeComposer(ledger: ledger)
        let entry = ChatEntry(
            role: "user", content: "一个问题", thread: nil
        )
        let base = composer.entryHeight(entry, dividerText: nil)
        let withSources = composer.entryHeight(
            entry, dividerText: nil, sources: sampleSources
        )
        XCTAssertEqual(
            withSources, base, accuracy: 0.5,
            "用户行高不因 sources 参数变化"
        )
    }
}
