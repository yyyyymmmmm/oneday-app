import OneDayDesign
import XCTest

/// 文件页分段控件落值钉（0.36.2，体验三件规格
/// §1.6）：Muse 文件页实测口径——总高 48、药丸
/// 高 36、内缩 6、左右边距 16。旧口径系目测高估
/// （总高曾达 60、药丸 52），本钉防任何一项回潮；
/// 同心关系（药丸＝总高−2×内缩、药丸圆角＝轨道
/// 圆角−内缩、双胶囊）一并钉住，改单值必同步改
/// 关系、不许单边漂移。
final class SegmentedControlSpecTests: XCTestCase {

    func testSegmentedControlAbsoluteValues() {
        XCTAssertEqual(SegmentedControlSpec.totalHeight, 48)
        XCTAssertEqual(SegmentedControlSpec.pillHeight, 36)
        XCTAssertEqual(SegmentedControlSpec.inset, 6)
        XCTAssertEqual(SegmentedControlSpec.horizontalMargin, 16)
    }

    func testSegmentedControlConcentricRelations() {
        // 药丸高＝总高 − 上下内缩
        XCTAssertEqual(
            SegmentedControlSpec.pillHeight,
            SegmentedControlSpec.totalHeight
                - 2 * SegmentedControlSpec.inset
        )
        // 轨道全胶囊：圆角＝总高/2
        XCTAssertEqual(
            SegmentedControlSpec.trackCorner,
            SegmentedControlSpec.totalHeight / 2
        )
        // 药丸同心收：圆角＝轨道圆角 − 内缩，且与
        // 药丸高/2 同值（药丸同为胶囊）
        XCTAssertEqual(
            SegmentedControlSpec.pillCorner,
            SegmentedControlSpec.trackCorner
                - SegmentedControlSpec.inset
        )
        XCTAssertEqual(
            SegmentedControlSpec.pillCorner,
            SegmentedControlSpec.pillHeight / 2
        )
    }
}
