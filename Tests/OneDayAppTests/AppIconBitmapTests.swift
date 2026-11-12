import UIKit
import XCTest
@testable import OneDayApp

/// §188 守护：设置页脚签名行与关于页 hero 的 App 图标
/// 必须取到真实位图（CFBundleIcons 通道与桌面图标同
/// 源）——通道失效（图标集改名/Info 形态变化）时本测
/// 先红，不许两处静默退回无图标形态。宿主为 App 本
/// 体，Bundle.main 即生产包，断言与线上一致。
final class AppIconBitmapTests: XCTestCase {

    func testAppIconBitmapResolves() throws {
        let image = try XCTUnwrap(
            AppIconBitmap.image,
            "CFBundleIcons 图标位图取不到——页脚/关于页图标会静默缺席"
        )
        // 最大位图口径：@3x 的 60pt 图标应为 180px 级，
        // 下限 120px 防取到小尺寸错图
        XCTAssertGreaterThanOrEqual(
            image.size.width * image.scale, 120,
            "取到的位图尺寸异常：\(image.size)@\(image.scale)x"
        )
        XCTAssertEqual(
            image.size.width, image.size.height,
            "App 图标应为正方形位图"
        )
    }

    func testAppIconViewBuilds() {
        // 两处消费点尺寸（页脚 19/关于 68）均可构造
        _ = AppIconView(size: 19, cornerRadius: 5)
        _ = AppIconView(size: 68, cornerRadius: 17)
    }
}
