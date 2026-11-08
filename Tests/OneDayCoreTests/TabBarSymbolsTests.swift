import OneDayCore
import UIKit
import XCTest

/// 底栏字形确定性定案（0.2.9，DESIGN-V4 §13）：字形高
/// 由 TabBarSymbols 的构造保证（SF Symbol 显式
/// pointSize 按 alpha 包围盒定标至 24pt）。本组测试以
/// 与工厂定标同一份 alpha 量法复核成品图：四个字形高
/// 须落 24±2——测试绿即尺寸定案，不依赖任何截图或渲
/// 染环境（0.2.6–0.2.8 三轮截图口径校准的教训在 §13）。
final class TabBarSymbolsTests: XCTestCase {
    /// 四个底栏字形：alpha 包围盒高 == 24±2
    func testGlyphHeightsAre24PlusMinus2() {
        for name in TabBarSymbols.names {
            let image = TabBarSymbols.image(named: name)
            let bounds = TabBarSymbols.alphaBounds(of: image)
            XCTAssertEqual(
                bounds.height, TabBarSymbols.glyphHeight, accuracy: 2,
                "\(name) 字形高 \(bounds.height)，应为 24±2"
            )
            XCTAssertGreaterThan(
                bounds.width, 0, "\(name) 字形宽应为正"
            )
        }
    }

    /// 模板渲染模式：底栏 .tint 墨色须生效（位图默认
    /// original 会让 tint 失效，0.2.7 踩过）
    func testImagesAreTemplateRendered() {
        for name in TabBarSymbols.names {
            XCTAssertEqual(
                TabBarSymbols.image(named: name).renderingMode,
                .alwaysTemplate, "\(name) 应为 alwaysTemplate"
            )
        }
    }

    /// 构造确定性：同名重复生成，尺寸逐位一致（缓存与
    /// 定标都不得漂移）
    func testConstructionIsDeterministic() {
        for name in TabBarSymbols.names {
            let first = TabBarSymbols.image(named: name).size
            let second = TabBarSymbols.image(named: name).size
            XCTAssertEqual(first, second, "\(name) 重复生成尺寸漂移")
        }
    }
}
