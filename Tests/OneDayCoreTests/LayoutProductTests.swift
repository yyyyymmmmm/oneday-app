import XCTest
@testable import OneDayCore

/// §251（换代包 2）排版产物层·Core 验收：
/// 四元组键的稳定性与三路失效、渲染计划分类、
/// 产物缓存的计数与清理
final class LayoutProductTests: XCTestCase {

    private let entryID = UUID()
    private var style: LayoutStyleKey {
        LayoutStyleKey(
            textStyle: "callout",
            sizeCategory: "UICTContentSizeCategoryL",
            boldText: false
        )
    }

    private func key(
        content: String = "正文内容",
        width: Double = 326,
        style: LayoutStyleKey? = nil
    ) -> LayoutProductKey {
        LayoutProductKey(
            entryID: entryID,
            content: content,
            width: width,
            style: style ?? self.style
        )
    }

    // MARK: - 键

    func testKeyStableForSameInputs() {
        XCTAssertEqual(key(), key())
        XCTAssertEqual(key().cacheKey, key().cacheKey)
    }

    func testKeyChangesWithContent() {
        XCTAssertNotEqual(key(content: "甲"), key(content: "乙"))
        // 同哈希不同字节数亦分家（双因子）
        XCTAssertNotEqual(
            key(content: "ab").contentByteCount,
            key(content: "abc").contentByteCount
        )
    }

    func testKeyChangesWithWidthAndStyleFactors() {
        XCTAssertNotEqual(key(width: 326), key(width: 200))
        XCTAssertNotEqual(
            key(),
            key(style: LayoutStyleKey(
                textStyle: "callout",
                sizeCategory: "UICTContentSizeCategoryAXL",
                boldText: false
            ))
        )
        XCTAssertNotEqual(
            key(),
            key(style: LayoutStyleKey(
                textStyle: "callout",
                sizeCategory: "UICTContentSizeCategoryL",
                boldText: true
            ))
        )
        XCTAssertNotEqual(
            key(),
            key(style: LayoutStyleKey(
                textStyle: "callout",
                sizeCategory: "UICTContentSizeCategoryL",
                boldText: false,
                fontVersion: LayoutStyleKey.currentFontVersion + 1
            ))
        )
        XCTAssertNotEqual(
            key(),
            key(style: LayoutStyleKey(
                textStyle: "callout",
                sizeCategory: "UICTContentSizeCategoryL",
                boldText: false,
                paragraphVersion:
                    LayoutStyleKey.currentParagraphVersion + 1
            ))
        )
    }

    func testKeyWidthQuantization() {
        // 布局提议宽的浮点抖动（<0.005）不许打成两键
        XCTAssertEqual(key(width: 326.001), key(width: 326.004))
        XCTAssertNotEqual(key(width: 326.001), key(width: 326.01))
    }

    // MARK: - 计划分类

    func testPlanClassifiesTextAndStructuralSegments() {
        let text = """
            第一段正文

            ```swift
            let a = 1
            ```

            > 引用一行

            | A | B |
            |---|---|
            | 1 | 2 |
            """
        let plan = LayoutProductPlan.plan(forAssistantText: text)
        XCTAssertEqual(plan.textSegments.count, 2)
        XCTAssertEqual(plan.textSegments[0].index, 0)
        if case .prose = plan.textSegments[0] {} else {
            XCTFail("首段应为 prose")
        }
        XCTAssertEqual(plan.textSegments[1].index, 2)
        if case .quote = plan.textSegments[1] {} else {
            XCTFail("第三段应为 quote")
        }
        // 代码块＋表格＝结构段 2
        XCTAssertEqual(plan.structuralSegmentCount, 2)
    }

    func testPlanEmptyAndPlainProse() {
        let empty = LayoutProductPlan.plan(forAssistantText: "")
        XCTAssertTrue(empty.textSegments.isEmpty)
        XCTAssertEqual(empty.structuralSegmentCount, 0)

        let plain = LayoutProductPlan.plan(
            forAssistantText: "就一段话"
        )
        XCTAssertEqual(plain.textSegments.count, 1)
        XCTAssertEqual(plain.structuralSegmentCount, 0)
    }

    // MARK: - 缓存

    func testCacheHitMissAndContainsAccounting() {
        let cache = LayoutProductCache()
        let productKey = key()
        let product = LayoutProduct(
            key: productKey,
            segments: [LayoutSegmentProduct(
                segmentIndex: 0, kind: .prose,
                attributed: NSAttributedString(string: "正文内容"),
                height: 20
            )],
            structuralSegmentCount: 0
        )
        XCTAssertNil(cache.product(for: productKey))
        XCTAssertFalse(cache.contains(productKey))
        // contains 只查不记账：上面一次 product 未命
        // 中 +1、contains 不动账
        XCTAssertEqual(cache.metrics().misses, 1)
        XCTAssertEqual(cache.metrics().hits, 0)

        cache.store(product)
        XCTAssertTrue(cache.contains(productKey))
        XCTAssertEqual(cache.product(for: productKey)?.textTotalHeight, 20)
        XCTAssertEqual(cache.metrics().hits, 1)

        cache.clear()
        XCTAssertNil(cache.product(for: productKey))
        XCTAssertEqual(cache.metrics().misses, 2)

        cache.resetMetrics()
        XCTAssertEqual(cache.metrics().hits, 0)
        XCTAssertEqual(cache.metrics().misses, 0)
    }

    func testProductTotalIsSegmentSum() {
        let product = LayoutProduct(
            key: key(),
            segments: [
                LayoutSegmentProduct(
                    segmentIndex: 0, kind: .prose,
                    attributed: NSAttributedString(string: "甲"),
                    height: 20.5
                ),
                LayoutSegmentProduct(
                    segmentIndex: 2, kind: .quote,
                    attributed: NSAttributedString(string: "乙"),
                    height: 17.5
                ),
            ],
            structuralSegmentCount: 1
        )
        XCTAssertEqual(product.textTotalHeight, 38.0, accuracy: 0.001)
        XCTAssertEqual(product.structuralSegmentCount, 1)
    }
}
