import OneDayCore
import XCTest

/// 已发图双封盒尺寸（0.36.19，§84.5）：等比、不出
/// 盒、只缩不放大。入参按 pt 口径喂数（用例的数值
/// 形状与真机截图同比例：竖长 1206×2622 即宽高比
/// 约 1:2.17 的手机截图）
final class ChatImageSizingTests: XCTestCase {

    func testVerticalScreenshotFitsByHeight() {
        // 竖长图：高先触盒（240），宽随比缩到约 110.4
        let size = ChatImageSizing.displaySize(
            for: CGSize(width: 1206, height: 2622)
        )
        XCTAssertEqual(size.height, 240, accuracy: 0.01)
        XCTAssertEqual(size.width, 110.4, accuracy: 0.1)
    }

    func testHorizontalImageFitsByWidth() {
        // 横长图：宽先触盒（220），高约 101.2
        let size = ChatImageSizing.displaySize(
            for: CGSize(width: 2622, height: 1206)
        )
        XCTAssertEqual(size.width, 220, accuracy: 0.01)
        XCTAssertEqual(size.height, 101.2, accuracy: 0.1)
    }

    func testSquareImageFitsByWidth() {
        // 方图：宽比高先触盒 → 220×220（不出 240 高）
        let size = ChatImageSizing.displaySize(
            for: CGSize(width: 1000, height: 1000)
        )
        XCTAssertEqual(size.width, 220, accuracy: 0.01)
        XCTAssertEqual(size.height, 220, accuracy: 0.01)
    }

    func testSmallImageIsNotUpscaled() {
        // 小于盒的图按原尺寸，只缩不放大
        let size = ChatImageSizing.displaySize(
            for: CGSize(width: 100, height: 80)
        )
        XCTAssertEqual(size.width, 100, accuracy: 0.01)
        XCTAssertEqual(size.height, 80, accuracy: 0.01)
    }

    func testExtremeThinImageStaysInBox() {
        // 极端细长：高钳 240、宽随比到 8，仍等比不出盒
        let size = ChatImageSizing.displaySize(
            for: CGSize(width: 100, height: 3000)
        )
        XCTAssertEqual(size.height, 240, accuracy: 0.01)
        XCTAssertEqual(size.width, 8, accuracy: 0.01)
        XCTAssertLessThanOrEqual(size.width, ChatImageSizing.maxWidth)
        XCTAssertLessThanOrEqual(size.height, ChatImageSizing.maxHeight)
    }

    func testDegenerateSizePassesThrough() {
        // 非正尺寸原样返回（防御口径，不替渲染层拿主意）
        let zero = ChatImageSizing.displaySize(
            for: CGSize(width: 0, height: 100)
        )
        XCTAssertEqual(zero.width, 0)
        XCTAssertEqual(zero.height, 100)
    }
}
