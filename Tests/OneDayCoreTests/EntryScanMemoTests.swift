import XCTest
@testable import OneDayCore

/// §199：条目级派生扫描备忘——等值性（与逐遍现算
/// 逐字相等）＋零重扫（同内容第二遍起未命中不增
/// 长）＋失效面（内容变/摘行集变即重算）
final class EntryScanMemoTests: XCTestCase {

    private let content = """
        前文一行
        [[deliver:dlv_0123456789abcdef0123]]
        MEDIA:/opt/data/cache/images/img_a.png
        /opt/data/files/report.png
        后文一行
        """

    override func setUp() {
        super.setUp()
        EntryScanMemo.removeAll()
        EntryScanMemo.resetMetrics()
    }

    func testScansEqualDirectComputation() {
        let entryID = UUID()
        let scans = EntryScanMemo.scans(
            entryID: entryID, content: content, remoteImagePaths: []
        )
        let delivery = DeliveryMarker.split(in: content)
        let media = MediaMarker.split(in: delivery.text)
        XCTAssertEqual(scans.delivery, delivery)
        XCTAssertEqual(scans.media, media)
        XCTAssertEqual(
            scans.inlineCandidates,
            FileRefDetector.inlineImageCandidates(
                in: media.text,
                excluding: [] + media.imagePaths
            )
        )
        XCTAssertEqual(
            Set(scans.standalonePaths),
            Set(
                FileRefDetector
                    .detectStandaloneAnchored(in: media.text)
                    .map(\.path)
            )
        )
        XCTAssertEqual(
            scans.media.imagePaths,
            ["/opt/data/cache/images/img_a.png"]
        )
        XCTAssertTrue(
            scans.standalonePaths.contains("/opt/data/files/report.png")
        )
    }

    func testSecondCallDoesNotRescan() {
        let entryID = UUID()
        _ = EntryScanMemo.scans(
            entryID: entryID, content: content, remoteImagePaths: []
        )
        _ = EntryScanMemo.scans(
            entryID: entryID, content: content, remoteImagePaths: []
        )
        let metrics = EntryScanMemo.metrics()
        XCTAssertEqual(metrics.scanMisses, 1, "同内容第二遍不许重扫")
        XCTAssertEqual(metrics.scanHits, 1)

        // 内容一变（流式增长/编辑）自动失效重算
        _ = EntryScanMemo.scans(
            entryID: entryID,
            content: content + "\n新增一行",
            remoteImagePaths: []
        )
        XCTAssertEqual(EntryScanMemo.metrics().scanMisses, 2)
    }

    func testDisplayTextMemoizedAndStripSetSensitive() {
        let entryID = UUID()
        let mediaText = "前文\n/opt/data/files/report.png\n后文"
        let strip: Set<String> = ["/opt/data/files/report.png"]

        let first = EntryScanMemo.displayText(
            entryID: entryID, mediaText: mediaText, stripPaths: strip
        )
        XCTAssertEqual(
            first,
            FileRefDetector.strippingStandaloneLines(
                in: mediaText, paths: strip
            )
        )
        XCTAssertFalse(first.contains("report.png"))

        _ = EntryScanMemo.displayText(
            entryID: entryID, mediaText: mediaText, stripPaths: strip
        )
        XCTAssertEqual(
            EntryScanMemo.metrics().stripMisses, 1,
            "同（正文，摘行集）第二遍不许重扫"
        )

        // 摘行集变化（存在性后到翻转）必须重算且结果不同
        let unstripped = EntryScanMemo.displayText(
            entryID: entryID, mediaText: mediaText, stripPaths: []
        )
        XCTAssertEqual(EntryScanMemo.metrics().stripMisses, 2)
        XCTAssertTrue(unstripped.contains("report.png"))
    }

    func testPlainTextMemoized() {
        let entryID = UUID()
        let markdown = "# 标题\n正文 **粗体** 一行"
        let first = EntryScanMemo.plainText(
            entryID: entryID, content: markdown
        )
        XCTAssertEqual(first, MessagePlainText.make(from: markdown))
        _ = EntryScanMemo.plainText(entryID: entryID, content: markdown)
        let metrics = EntryScanMemo.metrics()
        XCTAssertEqual(metrics.plainMisses, 1)
        XCTAssertEqual(metrics.plainHits, 1)
    }

    /// §333：facet 路径并集与逐遍现算（五源并集
    /// 原式）逐字相等——备忘只许省算、不许改值
    func testFacetPathsEqualDirectComputation() {
        let entryID = UUID()
        let paths = EntryScanMemo.facetPaths(
            entryID: entryID, content: content,
            remoteImagePaths: []
        )
        let scans = EntryScanMemo.scans(
            entryID: entryID, content: content,
            remoteImagePaths: []
        )
        var expected = Set<String>()
        expected.formUnion(scans.media.imagePaths)
        expected.formUnion(
            scans.inlineCandidates.map(\.path)
        )
        expected.formUnion(scans.standalonePaths)
        let whole = FileRefDetector.wholeMessagePath(
            in: scans.media.text
        )
        if let whole { expected.insert(whole.path) }
        let anchored = FileRefDetector
            .detectStandaloneAnchored(
                in: content,
                excluding: [] + scans.media.imagePaths
                    + scans.inlineCandidates.map(\.path)
                    + (whole.map { [$0.path] } ?? [])
            )
        expected.formUnion(anchored.map(\.path))
        XCTAssertEqual(paths, expected.sorted())
        XCTAssertTrue(
            paths.contains("/opt/data/cache/images/img_a.png")
        )
        XCTAssertTrue(
            paths.contains("/opt/data/files/report.png")
        )
    }

    /// §333：同（条目，内容，远端图集）第二遍起
    /// 零重扫；内容变／条目变即失效重算
    func testFacetPathsMemoized() {
        let entryID = UUID()
        _ = EntryScanMemo.facetPaths(
            entryID: entryID, content: content,
            remoteImagePaths: []
        )
        _ = EntryScanMemo.facetPaths(
            entryID: entryID, content: content,
            remoteImagePaths: []
        )
        var metrics = EntryScanMemo.metrics()
        XCTAssertEqual(
            metrics.facetMisses, 1, "同内容第二遍不许重扫"
        )
        XCTAssertEqual(metrics.facetHits, 1)

        _ = EntryScanMemo.facetPaths(
            entryID: entryID,
            content: content + "\n/opt/data/files/other.png",
            remoteImagePaths: []
        )
        metrics = EntryScanMemo.metrics()
        XCTAssertEqual(metrics.facetMisses, 2, "内容变必须重算")

        _ = EntryScanMemo.facetPaths(
            entryID: UUID(), content: content,
            remoteImagePaths: []
        )
        XCTAssertEqual(
            EntryScanMemo.metrics().facetMisses, 3,
            "条目变必须重算"
        )
    }
}
