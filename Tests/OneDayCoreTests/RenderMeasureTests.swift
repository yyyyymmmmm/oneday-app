import OneDayCore
import OneDayDesign
import UIKit
import XCTest

/// 渲染量测自证（0.3.8 证据纪律）：在模拟器里离线渲染
/// SF Symbol 与文字，按像素 alpha 取样，给出与 fixlist
/// 同类口径的复量数——图标墨迹密度 %（紧致 alpha 包围
/// 盒口径，另附 44pt 格口径）、字形墨高 pt、笔画宽 pt。
/// 每项都 print 一行 MEASURE…，CI 日志可 grep 复核。
/// 方法与口径全文记在 DESIGN-V4 §24.1。注意：本测试只
/// 量测、不产图、不落盘，没有任何截图工作流（红线）。
final class RenderMeasureTests: XCTestCase {
    // MARK: - 取样基础设施

    private struct InkStats {
        /// 紧致包围盒内的墨迹密度（0–1）
        var density: Double
        /// 44pt 方格口径密度（格大于字形时按实际边长）
        var cellDensity: Double
        var tightWidthPt: CGFloat
        var tightHeightPt: CGFloat
    }

    /// 像素 alpha 分析：alpha>12 记墨；紧致盒＝墨像素的
    /// 最小包围盒；密度与尺寸都以 image.scale 换算回 pt
    private func analyze(_ image: UIImage) -> InkStats? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width
        let h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1, ink = 0
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 12 {
                ink += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        let tightW = Double(maxX - minX + 1)
        let tightH = Double(maxY - minY + 1)
        let scale = Double(image.scale)
        let cellPx = 44.0 * scale
        return InkStats(
            density: Double(ink) / (tightW * tightH),
            cellDensity: Double(ink) / (cellPx * cellPx),
            tightWidthPt: CGFloat(tightW / scale),
            tightHeightPt: CGFloat(tightH / scale)
        )
    }

    private func symbol(
        _ name: String, size: CGFloat,
        weight: UIImage.SymbolWeight = .regular
    ) -> UIImage? {
        UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: size, weight: weight
            )
        )
    }

    private func report(_ tag: String, _ name: String, _ stats: InkStats) {
        print(String(
            format: "MEASURE %@ %@ density=%.3f cell=%.3f tight=%.1fx%.1fpt",
            tag, name, stats.density, stats.cellDensity,
            Double(stats.tightWidthPt), Double(stats.tightHeightPt)
        ))
    }

    // （0.4.0 删：第 1/2 条自绘底栏量测——底栏回原生
    // TabView 后字形尺寸与呈现由系统决定，自绘断言随
    // TabBarLayout 一并退役，审计 §3.2）

    // MARK: - 第 15/24 条：抽屉名单与底条字形（18/17 regular）

    func testDrawerSymbolInk() throws {
        for pair in TabBarSymbols.all {
            let image = try XCTUnwrap(
                symbol(pair.normal, size: FrameworkIcon.drawerGlyphSize),
                "\(pair.id) 名单字形渲染失败"
            )
            let stats = try XCTUnwrap(analyze(image))
            report("drawer", pair.normal, stats)
            XCTAssertTrue(
                (0.05...0.45).contains(stats.density),
                "\(pair.id) 名单密度 \(stats.density) 出带"
            )
        }
        let gear = try XCTUnwrap(
            symbol("gearshape", size: FrameworkIcon.drawerBarGlyphSize)
        )
        let gearStats = try XCTUnwrap(analyze(gear))
        report("drawer-bar", "gearshape", gearStats)
    }

    // MARK: - 第 14 条：设置页行图标同列密度（17 regular）

    func testSettingsSymbolInk() throws {
        let names = [
            "server.rack", "rectangle.stack.person.crop",
            "rectangle.portrait.and.arrow.right", "brain",
            "puzzlepiece.extension", "clock.arrow.2.circlepath",
            "bubble.left.and.text.bubble.right", "text.bubble",
            "key", "chart.bar", "network", "arrow.clockwise",
            "doc.text", "paintpalette",
        ]
        var densities: [String: Double] = [:]
        for name in names {
            let image = try XCTUnwrap(
                symbol(name, size: FrameworkIcon.settingsGlyphSize),
                "\(name) 渲染失败"
            )
            let stats = try XCTUnwrap(analyze(image))
            report("settings", name, stats)
            densities[name] = stats.density
            // 一致性口径（首轮实测后定，见 §24）：紧致盒
            // 密度量的是字形内部填充率，紧凑字形（network
            // 的球面网格生来填满包围盒）天生偏高、不是
            // 「复杂度离群」信号；同列一致性看槽位格口径
            // （28 槽内实际墨覆盖）＋紧致值只设防实心件的
            // 上限（.fill 件同口径 0.72+）
            XCTAssertLessThanOrEqual(
                stats.cellDensity, 0.10,
                "\(name) 格口径密度 \(stats.cellDensity) 离群"
            )
            XCTAssertLessThanOrEqual(
                stats.density, 0.55,
                "\(name) 紧致密度 \(stats.density) 达实心件量级"
            )
        }
        // 同列一致性：最密与最疏不许差出 2.5 倍（复杂度档
        // 统一的量化口径；离群者要在销账里点名换形）
        let values = densities.values
        if let lo = values.min(), let hi = values.max(), lo > 0 {
            print(String(
                format: "MEASURE settings-spread min=%.3f max=%.3f ratio=%.2f",
                lo, hi, hi / lo
            ))
            XCTAssertLessThanOrEqual(hi / lo, 2.5, "设置列密度离散过大")
        }
    }

    // MARK: - 第 32 条：＋笔画宽（15pt 目标约 1.8）

    func testPlusStrokeWidth() throws {
        for size in [FrameworkIcon.composerGlyphSize, 16.0] {
            let image = try XCTUnwrap(symbol("plus", size: CGFloat(size)))
            guard let cg = image.cgImage else { throw XCTSkip("无 cgImage") }
            let w = cg.width, h = cg.height
            var data = [UInt8](repeating: 0, count: w * h * 4)
            guard let ctx = CGContext(
                data: &data, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw XCTSkip("无 context") }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            // 紧致盒上 1/4 行只穿竖笔：最长墨游程＝笔宽
            var minY = h, maxY = -1
            for y in 0..<h {
                for x in 0..<w where data[(y * w + x) * 4 + 3] > 12 {
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            let probeY = minY + (maxY - minY) / 4
            var run = 0, best = 0
            for x in 0..<w {
                if data[(probeY * w + x) * 4 + 3] > 12 {
                    run += 1; best = max(best, run)
                } else { run = 0 }
            }
            let strokePt = Double(best) / Double(image.scale)
            print(String(
                format: "MEASURE plus-stroke size=%.0f stroke=%.2fpt",
                Double(size), strokePt
            ))
            if size == FrameworkIcon.composerGlyphSize {
                XCTAssertLessThanOrEqual(
                    strokePt, 2.2, "＋笔画 \(strokePt)pt 过粗（目标约 1.8）"
                )
            }
        }
    }

    // MARK: - 第 4/29 条：字形墨高

    private func inkHeight(_ text: String, font: UIFont) -> CGFloat? {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: UIColor.black,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in
                (text as NSString).draw(at: .zero, withAttributes: attrs)
            }
        return analyze(image)?.tightHeightPt
    }

    // （testTitleInkHeights 已于 0.4.0 删除：其钉死对象
    // ——自绘设置标题 30 bold 与气泡 17pt 显式字号——随
    // TypeScale 废止与 pageTitleSection 删除而不存在，
    // 字体回归语义样式后无自设尺寸可量，审计 §3.1）

    // MARK: - 气泡封存色（0.4.1，用户 10:07 点名改）

    /// 0.4.0 曾把气泡两色改挂 systemGray5/6，用户真机
    /// 判「发紫灰、深浅难分」——本版回封存中性灰直给。
    /// 钉三件事：①浅色解析值逐一等于封存 hex（助手
    /// #E9EAEC／用户 #F0F0F2）；②中性无色偏（浅暗两
    /// 环境下 |R−B| 都 ≤2/255，systemGray 的蓝紫倾向
    /// 约 5/255 起、过不了这条）；③深浅档差在（浅色
    /// 助手深于用户）。selectionFill 非气泡、维持系统
    /// 灰阶挂接不变
    func testBubbleColorsAreSealedNeutralGrays() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            UIColor(Palette.bubbleFill).resolvedColor(with: light),
            UIColor(
                red: 0xE9 / 255.0, green: 0xEA / 255.0,
                blue: 0xEC / 255.0, alpha: 1
            )
        )
        XCTAssertEqual(
            UIColor(Palette.userBubbleFill).resolvedColor(with: light),
            UIColor(
                red: 0xF0 / 255.0, green: 0xF0 / 255.0,
                blue: 0xF2 / 255.0, alpha: 1
            )
        )
        for traits in [light, dark] {
            for color in [Palette.bubbleFill, Palette.userBubbleFill] {
                var r: CGFloat = 0, g: CGFloat = 0
                var b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).resolvedColor(with: traits)
                    .getRed(&r, green: &g, blue: &b, alpha: &a)
                XCTAssertLessThanOrEqual(
                    abs(r - b), 2.0 / 255.0,
                    "气泡色不许带蓝紫倾向（R 与 B 分量差超限）"
                )
            }
        }
        var assistantR: CGFloat = 0, aG: CGFloat = 0
        var aB: CGFloat = 0, aA: CGFloat = 0
        var userR: CGFloat = 0, uG: CGFloat = 0
        var uB: CGFloat = 0, uA: CGFloat = 0
        UIColor(Palette.bubbleFill).resolvedColor(with: light)
            .getRed(&assistantR, green: &aG, blue: &aB, alpha: &aA)
        UIColor(Palette.userBubbleFill).resolvedColor(with: light)
            .getRed(&userR, green: &uG, blue: &uB, alpha: &uA)
        XCTAssertLessThan(assistantR, userR, "浅色下助手泡须深于用户泡")
        XCTAssertEqual(
            UIColor(Palette.selectionFill).resolvedColor(with: light),
            UIColor.systemGray5.resolvedColor(with: light)
        )
    }
}
