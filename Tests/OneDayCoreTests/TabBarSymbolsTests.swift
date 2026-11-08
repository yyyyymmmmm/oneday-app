import OneDayCore
import UIKit
import XCTest

/// 底栏字形定版（0.3.1，DESIGN-V4 §16）：图标改由系统
/// 符号渲染器按定版 SymbolConfiguration 直出，本组测试
/// 只钉可钉的——配置三值（pointSize 22／.regular／
/// .medium）与符号名清单。0.2.9 的 alpha 包围盒量高断
/// 言已随烘焙路线一并删除：几何定标管不住描边与底栏
/// 二次缩放，真机四轮打回的定因与止损条款在 §16。
final class TabBarSymbolsTests: XCTestCase {
    /// 符号清单：四枚、顺序与 ContentView 条目同序
    func testSymbolNamesAreTheFourTabItems() {
        XCTAssertEqual(TabBarSymbols.names, [
            "bubble.left.and.bubble.right",
            "chart.line.uptrend.xyaxis",
            "folder",
            "slider.horizontal.3",
        ])
    }

    /// 定版配置三值：字号对齐 Muse 真机字形实测
    /// （≈21.7–22.3pt），字重 regular 不许加粗凑数
    func testConfigurationSpecIsPinned() {
        XCTAssertEqual(TabBarSymbols.pointSize, 22)
        XCTAssertEqual(TabBarSymbols.weight, .regular)
        XCTAssertEqual(TabBarSymbols.scale, .medium)
    }

    /// 配置行为面：定版配置出的图与独立按同三值构造的
    /// 配置出的图尺寸一致（SymbolConfiguration 无公开
    /// 读回口，以渲染结果钉住配置确实由三值构成）
    func testConfigurationProducesSpecSizedSymbols() {
        let reference = UIImage.SymbolConfiguration(
            pointSize: 22, weight: .regular, scale: .medium
        )
        for name in TabBarSymbols.names {
            let expected = UIImage(
                systemName: name, withConfiguration: reference
            )
            let actual = TabBarSymbols.image(named: name)
            XCTAssertEqual(
                actual.size, expected?.size,
                "\(name) 尺寸与定版配置不符"
            )
        }
    }

    /// 成品必须是系统符号图（isSymbolImage）：UITabBar
    /// 对符号图走符号管线渲染；普通位图会被当照片二次
    /// 缩放——那正是 0.2.9 烘焙路线的病根之一
    func testImagesAreSystemSymbols() {
        for name in TabBarSymbols.names {
            let image = TabBarSymbols.image(named: name)
            XCTAssertTrue(
                image.isSymbolImage, "\(name) 应为系统符号图"
            )
            XCTAssertGreaterThan(image.size.height, 0)
            XCTAssertLessThanOrEqual(
                image.size.height, 30,
                "\(name) 图高异常（定版 22pt 配置不应出大图）"
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
}
