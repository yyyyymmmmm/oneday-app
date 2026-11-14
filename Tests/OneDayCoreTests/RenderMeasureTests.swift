import OneDayCore
import OneDayDesign
import SwiftUI
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

    // MARK: - 第 15/24 条：抽屉名单与底条字形
    // 0.22.0：尺寸随令牌追认 27、字重随定版 light（探
    // 针实测带 0.217–0.290，旧 0.05–0.45 闸继续有效）
    // 0.24.0：尺寸随令牌改 21、字重改 regular（用户当
    // 日指令：符号与文字同档）；闸带 0.05–0.45 先沿用
    // （24pt regular 同符号族实测 0.267–0.353 在带内），
    // 以 CI MEASURE 复核为准

    func testDrawerSymbolInk() throws {
        for pair in TabBarSymbols.all {
            let image = try XCTUnwrap(
                symbol(
                    pair.normal, size: FrameworkIcon.drawerGlyphSize,
                    weight: .regular
                ),
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

    // MARK: - 0.4.5：底栏四格符号墨迹（24pt，底栏渲染尺寸）

    /// 底栏换本体路线的量测闸（§30.7）：四格按底栏实
    /// 际渲染尺寸复量，print MEASURE 供 CI 日志复核；
    /// 断言取线条画法档的上限带（格口径 ≤0.12、紧致
    /// ≤0.42——.fill 件同口径 0.72+ 在带外；被换掉的
    /// 两格旧符号同口径数见 §30.7 对照表）。历史
    /// 「Muse 13–21%」是真机截图整格口径、与渲染口
    /// 径不可直接比数（§24.1），本闸只作同口径对照
    /// 与防实心回潮，不冒充截图口径
    /// 0.22.0：字重随定版 regular→light（24pt 实测紧
    /// 致 0.222–0.329、格口径 0.063–0.093，两闸均在
    /// 带内、闸值不变）
    func testTabBarSymbolInk() throws {
        for pair in TabBarSymbols.all {
            let image = try XCTUnwrap(
                symbol(pair.normal, size: 24, weight: .light),
                "\(pair.id) 底栏字形渲染失败"
            )
            let stats = try XCTUnwrap(analyze(image))
            report("tab", pair.normal, stats)
            XCTAssertLessThanOrEqual(
                stats.cellDensity, 0.12,
                "\(pair.id) 格口径密度 \(stats.cellDensity) 出线条画法档"
            )
            XCTAssertLessThanOrEqual(
                stats.density, 0.42,
                "\(pair.id) 紧致密度 \(stats.density) 出线条画法档"
            )
        }
    }

    // MARK: - 第 14 条：设置页行图标同列密度
    // 0.22.0：量测尺寸随现行渲染 17→28（FrameworkIcon
    // .settingsGlyphSize 同步追认）；名单换现行行图标
    // 全集（17 件：退役的断开/调色盘字形出列、管理组
    // 三件与 cable.connector/circle.lefthalf.filled 入
    // 列）；格口径闸按面积比 (28/17)² 重新校准

    func testSettingsSymbolInk() throws {
        // 0.24.0：名单随设置页换符号同步——brain→
        // memorychip、双泡宽字形→bubble.left、
        // desktopcomputer→display、档案→archivebox、
        // 外观→sun.max（换符号取舍见 §51）；量测尺寸
        // 随令牌 28→21，闸值先沿用 28pt 校准值、以 CI
        // MEASURE 分布复核（格口径随面积比约 ×0.56 收
        // 缩、只会更疏；紧致口径与尺寸弱相关）
        let names = [
            "server.rack", "archivebox",
            "key", "memorychip",
            "puzzlepiece.extension", "clock.arrow.2.circlepath",
            "bubble.left", "cable.connector",
            "text.bubble", "chart.bar", "network", "arrow.clockwise",
            "doc.text", "sun.max",
            "chart.xyaxis.line", "display", "folder",
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
                stats.cellDensity, 0.32,
                "\(name) 格口径密度 \(stats.cellDensity) 离群（21pt 沿用 28pt 校准闸）"
            )
            // 0.22.0 按 28pt 实测全集重新校准：全列紧致
            // 密度 0.252–0.631，上限是 cable.connector
            // ——紧致盒仅 9pt 宽的窄高字形、读数被窄盒
            // 放大（其格口径 0.092 反为全列最疏）；防实
            // 心线的本意是挡 .fill 件（同口径 0.72+），
            // 闸取 0.68 仍在其下、点名此件为形态离群
            XCTAssertLessThanOrEqual(
                stats.density, 0.68,
                "\(name) 紧致密度 \(stats.density) 达实心件量级（21pt 沿用 28pt 校准闸）"
            )
        }
        // 同列一致性：最密与最疏的倍数（复杂度档统一的
        // 量化口径；离群者要在销账里点名）。0.22.0 按
        // 28pt 实测分布（0.252–0.631、比值 2.50）把闸
        // 校准到 3.0：上限由 cable.connector 的窄盒形
        // 态主导（见上注）、下限 arrow.clockwise 0.252
        // 是正常细线字形——2.5 的旧闸在新尺寸下把正常
        // 分布误判为离散，3.0 仍能拦住真离群（整列换
        // 实心件时比值与绝对值双双出线）
        let values = densities.values
        if let lo = values.min(), let hi = values.max(), lo > 0 {
            print(String(
                format: "MEASURE settings-spread min=%.3f max=%.3f ratio=%.2f",
                lo, hi, hi / lo
            ))
            XCTAssertLessThanOrEqual(hi / lo, 3.0, "设置列密度离散过大")
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

    // MARK: - 气泡令牌色（0.6.1，OpenMuse 接管）

    /// 0.4.1 曾钉封存中性灰（助手 #E9EAEC／用户
    /// #F0F0F2＋双泡中性断言）；0.6.1 用户亲令配色改用
    /// OpenMuse，封存口径正式让位，本测试改钉它的令牌：
    /// ①浅色解析值＝OpenMuse 原值（助手泡 #EEEEF0＝
    /// chat.tsx:593、用户泡 #C8E7FF＝colors.blue、
    /// selectionFill #F0F1F2＝底栏激活 App.tsx:464）；
    /// ②暗色解析值——0.36.1 批一B 起助手泡改挂语义
    /// 三级面 #2C2C2E（旧派生 #272E33 退役，见下方语
    /// 义梯专钉）；用户泡取主题表 blueDark #1473C8；
    /// ③浅色助手泡守近中性（|R−B|＝2/255≤4——用户泡
    /// 是它的标志浅蓝、不受中性约束；旧「助手深于用
    /// 户」序断言随其语言撤销：它本貌即用户泡更醒目）
    func testBubbleColorsFollowOpenMuseTokens() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            UIColor(Palette.bubbleFill).resolvedColor(with: light),
            UIColor(
                red: 0xEE / 255.0, green: 0xEE / 255.0,
                blue: 0xF0 / 255.0, alpha: 1
            )
        )
        XCTAssertEqual(
            UIColor(Palette.userBubbleFill).resolvedColor(with: light),
            UIColor(
                red: 0xC8 / 255.0, green: 0xE7 / 255.0,
                blue: 0xFF / 255.0, alpha: 1
            )
        )
        XCTAssertEqual(
            UIColor(Palette.bubbleFill).resolvedColor(with: dark),
            UIColor(
                red: 0x2C / 255.0, green: 0x2C / 255.0,
                blue: 0x2E / 255.0, alpha: 1
            )
        )
        XCTAssertEqual(
            UIColor(Palette.userBubbleFill).resolvedColor(with: dark),
            UIColor(
                red: 0x14 / 255.0, green: 0x73 / 255.0,
                blue: 0xC8 / 255.0, alpha: 1
            )
        )
        var r: CGFloat = 0, g: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0
        UIColor(Palette.bubbleFill).resolvedColor(with: light)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThanOrEqual(
            abs(r - b), 4.0 / 255.0,
            "浅色助手泡须守近中性（OpenMuse #EEEEF0 原貌）"
        )
        // selectionFill（0.6.1）：OpenMuse 底栏激活项原值
        XCTAssertEqual(
            UIColor(Palette.selectionFill).resolvedColor(with: light),
            UIColor(
                red: 0xF0 / 255.0, green: 0xF1 / 255.0,
                blue: 0xF2 / 255.0, alpha: 1
            )
        )
    }

    /// 抽屉专用选中填充（§225，Muse 对齐三项包）：
    /// selectionFill 本体不动（上一测已钉 #F0F1F2），
    /// 抽屉三行改走 drawerSelectionFill——浅档解析钉
    /// #E4E5E7、且压抽屉面板合成面（thinMaterial 压
    /// pageBG，真机截图实测 #F2F2F2）逐通道 Δ≥10；
    /// 暗档解析钉三级面 #2C2C2E、压面板暗档近似面
    /// （材质压 systemBackground 的二级面级 #1C1C1E）
    /// 逐通道 Δ≥10。Δ 以 0–255 通道值计
    func testDrawerSelectionFillDeepenedForMaterialPanel() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        let pillLight = UIColor(Palette.drawerSelectionFill)
            .resolvedColor(with: light)
        XCTAssertEqual(
            pillLight,
            UIColor(
                red: 0xE4 / 255.0, green: 0xE5 / 255.0,
                blue: 0xE7 / 255.0, alpha: 1
            )
        )
        let pillDark = UIColor(Palette.drawerSelectionFill)
            .resolvedColor(with: dark)
        XCTAssertEqual(
            pillDark,
            UIColor(
                red: 0x2C / 255.0, green: 0x2C / 255.0,
                blue: 0x2E / 255.0, alpha: 1
            )
        )
        func channels(_ color: UIColor) -> [CGFloat] {
            var r: CGFloat = 0, g: CGFloat = 0
            var b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [r * 255, g * 255, b * 255]
        }
        let panelLight = channels(UIColor(
            red: 0xF2 / 255.0, green: 0xF2 / 255.0,
            blue: 0xF2 / 255.0, alpha: 1
        ))
        let panelDark = channels(UIColor(
            red: 0x1C / 255.0, green: 0x1C / 255.0,
            blue: 0x1E / 255.0, alpha: 1
        ))
        for (index, pair) in zip(
            channels(pillLight), panelLight
        ).enumerated() {
            XCTAssertGreaterThanOrEqual(
                abs(pair.0 - pair.1), 10,
                "浅档选中垫压面板合成面通道 \(index) Δ 须 ≥10"
            )
        }
        for (index, pair) in zip(
            channels(pillDark), panelDark
        ).enumerated() {
            XCTAssertGreaterThanOrEqual(
                abs(pair.0 - pair.1), 10,
                "暗档选中垫压面板近似面通道 \(index) Δ 须 ≥10"
            )
        }
    }

    /// 分量级解析断言（0.36.1）：语义色含 α，逐分量带
    /// 容差比对（系统常量为精确值，容差只吸收浮点差）
    private func assertResolved(
        _ color: Color, dark: Bool,
        equals expected: (r: Double, g: Double, b: Double, a: Double),
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let traits = UITraitCollection(
            userInterfaceStyle: dark ? .dark : .light
        )
        var r: CGFloat = 0, g: CGFloat = 0
        var b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits)
            .getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(
            Double(r), expected.r, accuracy: 0.01,
            "\(label) R", file: file, line: line
        )
        XCTAssertEqual(
            Double(g), expected.g, accuracy: 0.01,
            "\(label) G", file: file, line: line
        )
        XCTAssertEqual(
            Double(b), expected.b, accuracy: 0.01,
            "\(label) B", file: file, line: line
        )
        XCTAssertEqual(
            Double(a), expected.a, accuracy: 0.01,
            "\(label) A", file: file, line: line
        )
    }

    /// 语义同一性断言（0.36.1）：系统语义色解析后是
    /// Display P3 空间分量（getRed 读数与 sRGB 文档值
    /// 不等，如 systemRed 暗档 G/B 分量互换量级），且
    /// 个别 α 常量与文档表不符（systemFill 暗 0.36、
    /// quaternaryLabel 暗 40/255）——这类令牌钉「解
    /// 析值与系统语义色本尊相等」，比分量钉更准
    private func assertSemantic(
        _ color: Color, dark: Bool, equals semantic: UIColor,
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let traits = UITraitCollection(
            userInterfaceStyle: dark ? .dark : .light
        )
        XCTAssertEqual(
            UIColor(color).resolvedColor(with: traits),
            semantic.resolvedColor(with: traits),
            label, file: file, line: line
        )
    }

    /// 暗档语义梯专钉（0.36.1，批一B／审计 D1–D6）：
    /// 0.6.1 的派生色板退役后，Palette 暗档解析值必须
    /// 逐项落在苹果语义梯上——背景三层（D1/D2）、标
    /// 签四级（D3）、描边（D4）、fill 阶梯（D5）、状
    /// 态色（D6）；末尾附浅档守恒三钉（浅色已定版、
    /// 本批一字未动的证据）
    func testDarkPaletteFollowsAppleSemanticTiers() {
        // 背景三层：base 三面同锚纯黑、卡 #1C1C1E、
        // 三级面 #2C2C2E（浮层与卡面拉开、D2 提级修复）
        assertResolved(
            Palette.pageBG, dark: true,
            equals: (0, 0, 0, 1), "pageBG 暗"
        )
        assertResolved(
            Palette.chatSurface, dark: true,
            equals: (0, 0, 0, 1), "chatSurface 暗"
        )
        assertResolved(
            Palette.settingsBG, dark: true,
            equals: (0, 0, 0, 1), "settingsBG 暗"
        )
        assertResolved(
            Palette.surface, dark: true,
            equals: (0x1C / 255.0, 0x1C / 255.0, 0x1E / 255.0, 1),
            "surface 暗"
        )
        assertResolved(
            Palette.bubbleFill, dark: true,
            equals: (0x2C / 255.0, 0x2C / 255.0, 0x2E / 255.0, 1),
            "bubbleFill 暗"
        )
        assertResolved(
            Palette.floatFill, dark: true,
            equals: (0x2C / 255.0, 0x2C / 255.0, 0x2E / 255.0, 1),
            "floatFill 暗"
        )
        assertResolved(
            Palette.fieldFill, dark: true,
            equals: (0x2C / 255.0, 0x2C / 255.0, 0x2E / 255.0, 1),
            "fieldFill 暗"
        )
        // 标签四级：label 纯白、次/弱/四级为 α 阶梯
        assertResolved(
            Palette.ink, dark: true,
            equals: (1, 1, 1, 1), "ink 暗"
        )
        assertResolved(
            Palette.bodyInk, dark: true,
            equals: (1, 1, 1, 1), "bodyInk 暗"
        )
        assertResolved(
            Palette.inkSecondary, dark: true,
            equals: (235.0 / 255.0, 235.0 / 255.0, 245.0 / 255.0, 0.60),
            "inkSecondary 暗"
        )
        assertResolved(
            Palette.inkMuted, dark: true,
            equals: (235.0 / 255.0, 235.0 / 255.0, 245.0 / 255.0, 0.30),
            "inkMuted 暗"
        )
        // 四级标签与系统色以「语义同一性」钉（见下方
        // assertSemantic 注：解析分量是 P3 空间值、且
        // quaternaryLabel 暗档 α 实测 40/255，分量钉
        // 会钉错口径）
        assertSemantic(
            Palette.inkQuaternary, dark: true,
            equals: .quaternaryLabel, "inkQuaternary 暗"
        )
        // 发丝描边：opaqueSeparator #38383A
        assertResolved(
            Palette.hairline, dark: true,
            equals: (0x38 / 255.0, 0x38 / 255.0, 0x3A / 255.0, 1),
            "hairline 暗"
        )
        // fill 阶梯与状态色：语义同一性钉（systemFill
        // 暗档 α 实测 0.36、secondarySystemFill 0.32，
        // 与 sRGB 文档表口径不同，以系统实测为准）
        assertSemantic(
            Palette.selectionFill, dark: true,
            equals: .systemFill, "selectionFill 暗"
        )
        assertSemantic(
            Palette.fillSecondary, dark: true,
            equals: .secondarySystemFill, "fillSecondary 暗"
        )
        assertSemantic(
            Palette.danger, dark: true,
            equals: .systemRed, "danger 暗"
        )
        assertSemantic(
            Palette.success, dark: true,
            equals: .systemGreen, "success 暗"
        )
        assertSemantic(
            Palette.warning, dark: true,
            equals: .systemOrange, "warning 暗"
        )
        // 浅档守恒：本批未动的三钉
        assertResolved(
            Palette.pageBG, dark: false,
            equals: (0xFC / 255.0, 0xFC / 255.0, 0xFC / 255.0, 1),
            "pageBG 浅"
        )
        assertResolved(
            Palette.surface, dark: false,
            equals: (1, 1, 1, 1), "surface 浅"
        )
        assertResolved(
            Palette.inkSecondary, dark: false,
            equals: (0x64 / 255.0, 0x6B / 255.0, 0x71 / 255.0, 1),
            "inkSecondary 浅"
        )
    }
}
