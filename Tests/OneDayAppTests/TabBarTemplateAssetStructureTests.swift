import OneDayCore
import UIKit
import XCTest

/// §403 结构钉测（§382 B1）＋§405 朝向门：底栏图标脱离
/// symbol 身份、改模板图资产。把守三件：①tabLabel 图标
/// 处不得回归 Image(systemName:)——iOS 26 宿主的 fill
/// 变体注入只作用于活 symbol image，改回符号路＝冷启
/// 实色复发（定因 DESIGN §403）；②五枚资产在生产包内
/// 解析得出、画布＝SF Symbols 官方导出几何（§405.5 改
/// 判：官方应用「将图像拷贝为」SVG，24pt／细体／中缩
/// 放，流程记录见 Scripts/make-tab-assets.swift）、模
/// 板渲染；③资产目录声明 Template 意图＋保矢量，目录
/// 改坏时先红、不静默回落。朝向只设结构特征钉（横带
/// ／重心／尾巴象限，容差为结构量级）：逐像素对账活
/// 符号的自研尺已按 §405.5 改判删除，朝向终验归用户
/// 真机冷启截图 verdict（DESIGN §405.5）。
final class TabBarTemplateAssetStructureTests: XCTestCase {

    private func repoFile(_ relative: String) throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
    }

    /// tabLabel 图标走资产、不走系统符号名
    func testTabLabelIconUsesAssetNotSystemName() throws {
        let src = try String(
            contentsOf: repoFile("Sources/OneDayApp/ContentView.swift"),
            encoding: .utf8
        )
        let start = try XCTUnwrap(
            src.range(of: "private func tabLabel"),
            "找不到 tabLabel"
        )
        let end = try XCTUnwrap(
            src.range(
                of: ".accessibilityLabel(pair.title)",
                range: start.lowerBound..<src.endIndex
            ),
            "找不到 tabLabel 的 accessibilityLabel 收尾"
        )
        let body = String(src[start.lowerBound..<end.upperBound])
        // 只扫代码行：注释里会正当提及被禁写法（如本函数
        // 的 §403 注），注释行不算回归（同仓结构钉惯例）
        let codeOnly = body
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(
            codeOnly.contains("Image(pair.asset)"),
            "§403：tabLabel 图标应走模板图资产 Image(pair.asset)"
        )
        XCTAssertFalse(
            codeOnly.contains("Image(systemName:"),
            "§403：tabLabel 图标不许回归 Image(systemName:)"
                + "——宿主 fill 注入的复发面"
        )
    }

    /// 五枚资产在宿主 App 包内解析：画布与 SF Symbols
    /// 官方导出 SVG 的 viewBox 一致（导出几何即设计几
    /// 何，§405.5），且为模板渲染（吃 tint、不自带色）
    func testTabAssetsResolveInAppBundle() {
        let expected: [(String, CGSize)] = [
            ("tab.chat", CGSize(width: 22.61, height: 19.9504)),
            ("tab.feed", CGSize(width: 16.5086, height: 20.8188)),
            ("tab.ideas", CGSize(width: 13.1644, height: 23.1)),
            ("tab.goals", CGSize(width: 21.935, height: 19.6953)),
            ("tab.files", CGSize(width: 27.7955, height: 19.5188)),
        ]
        XCTAssertEqual(TabBarSymbols.all.map(\.asset), expected.map(\.0))
        for (name, size) in expected {
            let image = UIImage(named: name)
            XCTAssertNotNil(
                image,
                "§403：资产 \(name) 在生产包内解析不出"
            )
            guard let image else { continue }
            XCTAssertEqual(
                image.size.width, size.width, accuracy: 0.6,
                "§405：\(name) 画布宽应为官方导出几何 \(size)"
            )
            XCTAssertEqual(
                image.size.height, size.height, accuracy: 0.6,
                "§405：\(name) 画布高应为官方导出几何 \(size)"
            )
            XCTAssertEqual(
                image.renderingMode, .alwaysTemplate,
                "§403：\(name) 应为模板渲染（吃 tint、不自带色）"
            )
        }
    }

    // MARK: §405 朝向特征钉（结构量级容差，§405.5）

    /// 墨迹图：图按自身尺寸以 10x 栅格化、alpha>0.5 取
    /// 墨。资产与活符号各自栅格化后都裁到墨迹框再比形
    /// 状分布——比的是字形自身的上下结构，与画布留白
    /// 无关；容差取结构量级，只拦整轴翻转这类形态反
    /// 转，不做逐点对账（§405.5 改判）。
    private func inkMap(
        of image: UIImage
    ) -> (w: Int, h: Int, ink: [Bool]) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 10
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: image.size, format: format
        )
        let rendered = renderer.image { _ in
            image.draw(
                in: CGRect(origin: .zero, size: image.size)
            )
        }
        let cg = rendered.cgImage!
        let w = cg.width, h = cg.height
        let data = cg.dataProvider!.data! as Data
        let bpr = cg.bytesPerRow
        var ink = [Bool](repeating: false, count: w * h)
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for y in 0..<h { for x in 0..<w {
                ink[y * w + x] = bytes[y * bpr + x * 4 + 3] > 127
            } }
        }
        return (w, h, ink)
    }

    private func liveSymbol(
        _ pair: TabSymbolPair
    ) -> UIImage? {
        UIImage(
            systemName: pair.normal
        )?.withConfiguration(
            UIImage.SymbolConfiguration(
                pointSize: 24, weight: .light
            )
        )
    }

    /// 裁到墨迹包围盒：形状分布与画布留白脱钩
    private func croppedToInk(
        _ m: (w: Int, h: Int, ink: [Bool])
    ) -> (w: Int, h: Int, ink: [Bool]) {
        var minX = m.w, minY = m.h, maxX = -1, maxY = -1
        for y in 0..<m.h { for x in 0..<m.w
            where m.ink[y * m.w + x] {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        } }
        guard maxX >= minX, maxY >= minY else { return m }
        let w = maxX - minX + 1, h = maxY - minY + 1
        var ink = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            ink[y * w + x] = m.ink[(y + minY) * m.w + (x + minX)]
        } }
        return (w, h, ink)
    }

    private func bandShare(
        _ m: (w: Int, h: Int, ink: [Bool]),
        band: Int, total: Double
    ) -> Double {
        let y0 = band * m.h / 6, y1 = (band + 1) * m.h / 6
        var c = 0
        for y in y0..<y1 { for x in 0..<m.w
            where m.ink[y * m.w + x] { c += 1 } }
        return total > 0 ? Double(c) / total : 0
    }

    private func centroidRow(
        _ m: (w: Int, h: Int, ink: [Bool])
    ) -> Double {
        var sum = 0.0, cnt = 0.0
        for y in 0..<m.h { for x in 0..<m.w
            where m.ink[y * m.w + x] {
            sum += Double(y); cnt += 1
        } }
        return cnt > 0 ? (sum / cnt) / Double(m.h) : 0
    }

    /// 朝向特征钉：资产与同名活符号（24pt light）的墨
    /// 迹形状分布同向——6 横带占比、重心行、chat 左带
    /// 尾巴特征。整轴翻转会把上下分布镜像、偏离远超容
    /// 差；同向字形的跨渲染器版式差在结构容差之内。
    /// 终验不在此例：朝向以用户真机冷启截图为准
    /// （§405.5）。
    func testTabAssetOrientationFeatures() throws {
        for pair in TabBarSymbols.all {
            let asset = try XCTUnwrap(UIImage(named: pair.asset))
            let live = try XCTUnwrap(liveSymbol(pair))
            let a = croppedToInk(inkMap(of: asset))
            let l = croppedToInk(inkMap(of: live))
            let totalA = Double(a.ink.filter { $0 }.count)
            let totalL = Double(l.ink.filter { $0 }.count)
            XCTAssertGreaterThan(totalA, 0, "§405：\(pair.asset) 无墨迹")
            guard totalA > 0, totalL > 0 else { continue }
            for band in 0..<6 {
                let shareA = bandShare(a, band: band, total: totalA)
                let shareL = bandShare(l, band: band, total: totalL)
                XCTAssertLessThanOrEqual(
                    abs(shareA - shareL), 0.10,
                    "§405：\(pair.asset) 第 \(band) 横带墨迹占比 "
                        + "\(shareA) 与活符号 \(shareL) 偏离——竖直分布不同向"
                )
            }
            XCTAssertLessThanOrEqual(
                abs(centroidRow(a) - centroidRow(l)), 0.06,
                "§405：\(pair.asset) 墨迹重心行与活符号偏离——上下分布不同向"
            )
            if pair.asset == "tab.chat" {
                // 尾巴特征：左带（x<w/4）下半墨减上半墨、
                // 占总墨比例——尾巴在左下时显著为正，翻
                // 转后变号
                func tail(_ m: (w: Int, h: Int, ink: [Bool]),
                          total: Double) -> Double {
                    var diff = 0
                    for y in 0..<m.h { for x in 0..<(m.w / 4)
                        where m.ink[y * m.w + x] {
                        diff += y >= m.h / 2 ? 1 : -1
                    } }
                    return total > 0 ? Double(diff) / total : 0
                }
                XCTAssertLessThanOrEqual(
                    abs(tail(a, total: totalA) - tail(l, total: totalL)),
                    0.08,
                    "§405：tab.chat 左带上下墨差（尾巴象限）与活符号偏离"
                )
            }
        }
    }

    /// 资产目录声明：Template 意图＋保矢量＋SVG 实物在位
    func testAssetCatalogDeclaresTemplateVector() throws {
        for pair in TabBarSymbols.all {
            let dir = try repoFile(
                "App/Resources/Assets.xcassets/\(pair.asset).imageset"
            )
            let json = try String(
                contentsOf: dir.appendingPathComponent("Contents.json"),
                encoding: .utf8
            )
            XCTAssertTrue(
                json.contains("\"template-rendering-intent\""),
                "§403：\(pair.asset) Contents.json 缺 Template 意图"
            )
            XCTAssertTrue(
                json.contains("\"template\""),
                "§403：\(pair.asset) Template 意图值异常"
            )
            XCTAssertTrue(
                json.contains("\"preserves-vector-representation\" : true"),
                "§403：\(pair.asset) 缺保矢量声明"
            )
            let svg = dir.appendingPathComponent("\(pair.asset).svg")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: svg.path),
                "§405：\(pair.asset) 矢量 SVG 缺失（官方导出实物）"
            )
        }
    }
}
