import OneDayCore
import XCTest

/// 图片查看器状态机钉（0.36.4，体验三件规格 §3）：
/// 索引夹紧、切页清缩放、放大禁翻页、chrome 只在
/// 卡态——查看器的全部呈现裁决在此，视图层回潮
/// （越界索引、缩放带页、沉浸态挂 chrome）先在此
/// 红。
final class ImageViewerLogicTests: XCTestCase {

    func testInitialIndexClampedIntoRange() {
        XCTAssertEqual(
            ImageViewerState(count: 5, initialIndex: 2).index, 2
        )
        XCTAssertEqual(
            ImageViewerState(count: 5, initialIndex: 99).index, 4
        )
        XCTAssertEqual(
            ImageViewerState(count: 5, initialIndex: -3).index, 0
        )
    }

    func testEmptyCollectionStaysAtZeroWithoutContent() {
        let state = ImageViewerState(count: 0, initialIndex: 4)
        XCTAssertEqual(state.index, 0)
        XCTAssertFalse(state.hasContent)
        XCTAssertEqual(ImageViewerState.clamped(7, count: 0), 0)
    }

    func testStartsInCardModeWithChromeAndPaging() {
        let state = ImageViewerState(count: 3, initialIndex: 0)
        XCTAssertEqual(state.mode, .card)
        XCTAssertTrue(state.chromeVisible)
        XCTAssertTrue(state.pagingEnabled)
        XCTAssertFalse(state.isZoomed)
    }

    func testSelectClampsAndClearsZoomOnPageChange() {
        var state = ImageViewerState(count: 4, initialIndex: 0)
        state.setZoomed(true)
        state.select(index: 2)
        XCTAssertEqual(state.index, 2)
        XCTAssertFalse(state.isZoomed)
        state.select(index: 42)
        XCTAssertEqual(state.index, 3)
        // 同页重选不误清缩放（分页控件回写同值时）
        state.setZoomed(true)
        state.select(index: 3)
        XCTAssertTrue(state.isZoomed)
    }

    func testZoomBlocksPaging() {
        var state = ImageViewerState(count: 3, initialIndex: 0)
        state.setZoomed(true)
        XCTAssertFalse(state.pagingEnabled)
        state.setZoomed(false)
        XCTAssertTrue(state.pagingEnabled)
    }

    func testToggleModeRoundTripAndImmersiveHidesChrome() {
        var state = ImageViewerState(count: 3, initialIndex: 1)
        state.toggleMode()
        XCTAssertEqual(state.mode, .immersive)
        XCTAssertFalse(state.chromeVisible)
        state.toggleMode()
        XCTAssertEqual(state.mode, .card)
        XCTAssertTrue(state.chromeVisible)
    }

    func testReturningToCardClearsZoom() {
        var state = ImageViewerState(count: 3, initialIndex: 0)
        state.toggleMode()
        state.setZoomed(true)
        XCTAssertTrue(state.isZoomed)
        state.toggleMode()
        XCTAssertEqual(state.mode, .card)
        XCTAssertFalse(state.isZoomed)
    }

    // MARK: - 卡态 fitted 尺寸

    func testFittedSizeKeepsAspectAndNeverUpscales() {
        // 横图装入 371×400：按宽定档
        let wide = ImageViewerLayout.fittedSize(
            imageWidth: 1200, imageHeight: 800,
            maxWidth: 371, maxHeight: 400
        )
        XCTAssertEqual(wide.width, 371, accuracy: 0.5)
        XCTAssertEqual(wide.height, 247, accuracy: 0.5)
        // 竖图：按高定档
        let tall = ImageViewerLayout.fittedSize(
            imageWidth: 800, imageHeight: 1200,
            maxWidth: 371, maxHeight: 400
        )
        XCTAssertEqual(tall.height, 400, accuracy: 0.5)
        XCTAssertEqual(tall.width, 267, accuracy: 0.5)
        // 小图不放大（原尺寸呈现）
        let small = ImageViewerLayout.fittedSize(
            imageWidth: 200, imageHeight: 100,
            maxWidth: 371, maxHeight: 400
        )
        XCTAssertEqual(small.width, 200, accuracy: 0.5)
        XCTAssertEqual(small.height, 100, accuracy: 0.5)
    }

    func testFittedSizeDegenerateInputFallsBackToSquare() {
        let fallback = ImageViewerLayout.fittedSize(
            imageWidth: 0, imageHeight: -5,
            maxWidth: 300, maxHeight: 500
        )
        XCTAssertEqual(fallback.width, 300, accuracy: 0.5)
        XCTAssertEqual(fallback.height, 300, accuracy: 0.5)
    }
}
