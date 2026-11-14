import OneDayCore
import UIKit
import XCTest

/// §217（Muse 对齐三项包，频道行品牌真图标钉死）：
/// Core 注册表测试只钉资产「名」，资产「实物」此前无
/// 人守——imageset 缺失/改名时抽屉频道行 `Image(asset)`
/// 静默空白（nil 回落只管未登记、无资产回落）。本测在
/// 宿主 App 包内逐行验：drawerList 全部行的
/// iconAssetName 必须非空且能解析出真实位图（官方原图
/// 均为近正方 App 图标级图面），缺失先红。
final class ChannelBrandAssetTests: XCTestCase {

    func testDrawerChannelBrandAssetsResolveToBitmaps() {
        XCTAssertFalse(
            ChannelRegistry.drawerList.isEmpty,
            "抽屉频道清单不应为空"
        )
        for channel in ChannelRegistry.drawerList {
            let assetName = channel.iconAssetName
            XCTAssertNotNil(
                assetName,
                "频道 \(channel.id) 未登记图标资产——抽屉行会回落 SF 符号"
            )
            guard let assetName else { continue }
            let image = UIImage(named: assetName)
            XCTAssertNotNil(
                image,
                "频道 \(channel.id) 的资产 \(assetName) 在生产包内解析不出位图"
            )
            guard let image else { continue }
            XCTAssertGreaterThan(
                image.size.width, 0,
                "频道 \(channel.id) 资产 \(assetName) 位图宽度异常"
            )
            // 官方 App 原图与 LocalHermes 定制图均为正方
            // 级图面（容差吸收个别资产的边距留白）
            XCTAssertEqual(
                image.size.width, image.size.height,
                accuracy: max(2, image.size.width * 0.05),
                "频道 \(channel.id) 资产 \(assetName) 应为近正方图面：\(image.size)"
            )
        }
    }
}
