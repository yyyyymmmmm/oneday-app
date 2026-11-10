import OneDayDesign
import XCTest

/// 图片查看器卡态落值钉（0.36.4，体验三件规格
/// §3.5）：Muse 录屏逐帧量测口径——卡边距 16、
/// 卡圆角 16、关闭钮 44、工具胶囊高 40。防任何
/// 一项凭手感漂移（分段控件「目测高估 15pt」的
/// 教训在前，量测值只许经新量测改）。
final class ImageViewerSpecTests: XCTestCase {

    func testImageViewerAbsoluteValues() {
        XCTAssertEqual(ImageViewerSpec.cardHorizontalMargin, 16)
        XCTAssertEqual(ImageViewerSpec.cardCorner, 16)
        XCTAssertEqual(ImageViewerSpec.closeButtonDiameter, 44)
        XCTAssertEqual(ImageViewerSpec.chromeCapsuleHeight, 40)
        XCTAssertEqual(ImageViewerSpec.chromeButtonWidth, 44)
    }

    func testChromeCapsuleWidthMatchesMeasuredCapsule() {
        // 实测胶囊宽 ≈93：两钮 44×2＋钮间隙 5 以内
        let width = ImageViewerSpec.chromeButtonWidth * 2
        XCTAssertGreaterThanOrEqual(width, 88)
        XCTAssertLessThanOrEqual(width + 6, 99)
        // 关闭钮直径即命中域下限（44 口径）
        XCTAssertGreaterThanOrEqual(
            ImageViewerSpec.closeButtonDiameter, 44
        )
    }
}
