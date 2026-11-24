import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §485 目标页全抄修复量测（与审计同一量测法：渲染
/// 帧墨迹投影，pt＝px÷scale）：五项对账——①复选框
/// 视觉尺寸 22×22 ②描边可测（opaqueSeparator 档墨
/// 迹量；对照旧 hairline 在同阈下测不到，审计 D4。
/// 半透明 separator 在 iOS 26 解析 α＝0.12、压白
/// 实渲 (232,232,232) 与 hairline 几乎无别——本套
/// 首跑实证，故描边定版 opaqueSeparator 实色档
/// (198,198,200)）③框顶与标题首行顶差 ≤3pt ④摘
/// 要行 pitch 19±1 ⑤行 pitch 102±6（附页题墨迹
/// 高＝24pt 档旁证、段头无底盘旁证）。渲染面＝组
/// 件本体（GoalCheckBox/GoalRowView/GoalGroup
/// Header/GoalsPageTitle），模拟器渲染帧、非真机
/// 帧——真机同位复核归用户 verdict，本套只钉实验
/// 室口径不冒充真机关账
@MainActor
final class GoalsCopy478MeasureTests: XCTestCase {

    // MARK: - 渲染与像素读数

    private struct Bitmap {
        let pxWidth: Int
        let pxHeight: Int
        let scale: CGFloat
        let rgba: [UInt8]

        var ptWidth: CGFloat { CGFloat(pxWidth) / scale }
        var ptHeight: CGFloat { CGFloat(pxHeight) / scale }

        /// 相对亮度（0 黑 – 1 白），透明像素按压白底合成
        func luminance(pxX: Int, pxY: Int) -> Double {
            guard pxX >= 0, pxX < pxWidth, pxY >= 0, pxY < pxHeight
            else { return 1 }
            let i = (pxY * pxWidth + pxX) * 4
            let a = Double(rgba[i + 3]) / 255.0
            func ch(_ v: UInt8) -> Double {
                a * (Double(v) / 255.0) + (1 - a) * 1.0
            }
            return 0.2126 * ch(rgba[i])
                + 0.7152 * ch(rgba[i + 1])
                + 0.0722 * ch(rgba[i + 2])
        }

        func luminance(ptX: CGFloat, ptY: CGFloat) -> Double {
            luminance(
                pxX: Int(ptX * scale), pxY: Int(ptY * scale)
            )
        }

        /// 区域内墨迹（lum<阈值）像素数（px）
        func inkCount(
            x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>,
            threshold: Double
        ) -> Int {
            var count = 0
            let x0 = max(0, Int(x.lowerBound * scale))
            let x1 = min(pxWidth - 1, Int(x.upperBound * scale))
            let y0 = max(0, Int(y.lowerBound * scale))
            let y1 = min(pxHeight - 1, Int(y.upperBound * scale))
            guard x1 >= x0, y1 >= y0 else { return 0 }
            for py in y0...y1 {
                for px in x0...x1
                where luminance(pxX: px, pxY: py) < threshold {
                    count += 1
                }
            }
            return count
        }

        /// 自 fromY 起首个有墨迹（lum<阈值、单行墨迹
        /// ≥minInkPx）的行（pt）；无则 nil
        func firstInkRow(
            fromY: CGFloat, x: ClosedRange<CGFloat>,
            threshold: Double, minInkPx: Int = 3
        ) -> CGFloat? {
            var y = fromY
            while y < ptHeight {
                if inkCount(
                    x: x, y: y...(y + 0.99), threshold: threshold
                ) >= minInkPx {
                    return y
                }
                y += 1
            }
            return nil
        }
    }

    private func render<V: View>(_ view: V) -> Bitmap {
        let wrapped = view
            .environment(\.colorScheme, .light)
            .environment(\.sizeCategory, .large)
        let renderer = ImageRenderer(content: wrapped)
        renderer.scale = 3
        let image = renderer.uiImage!
        let cg = image.cgImage!
        let w = cg.width
        let h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(
            data: &data, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // 朝向口径（§485 量测首跑实证）：renderer 的
        // CGImage 直绘进本上下文即 row0＝图顶；再加
        // translate+scale(1,-1) 翻转会把图上下颠倒
        // （首跑因此误读：摘要三带被当成标题在上、
        // 复选框被读成沉底——分件对照剖面逐像素比
        // 对后定因），此处不作任何翻转
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Bitmap(
            pxWidth: w, pxHeight: h, scale: 3, rgba: data
        )
    }

    // MARK: - ①② 复选框：视觉 22×22＋描边可测

    func testCheckboxVisualBox22AndStrokeMeasurable() {
        let bmp = render(
            GoalCheckBox(done: false) {}
                .background(Color.white)
        )
        // 布局恒 22（44 命中层经 -11 padding 抵消）
        XCTAssertEqual(bmp.ptWidth, 22, accuracy: 1)
        XCTAssertEqual(bmp.ptHeight, 22, accuracy: 1)
        print("MEASURE478 checkbox size: \(bmp.ptWidth)x\(bmp.ptHeight)pt")
        // 描边墨迹：opaqueSeparator 档（压白
        // ≈(198,198,200)、亮度 ≈0.78）在 0.88 阈
        // 下应成环（环面积 ≈123pt²、@3x 约
        // 1100px，取下限 400 防抗锯齿口径差）
        let ink = bmp.inkCount(
            x: 0...22, y: 0...22, threshold: 0.88
        )
        XCTAssertGreaterThan(
            ink, 400, "opaqueSeparator 描边应可测（实测 \(ink)px）"
        )
        print("MEASURE478 checkbox stroke ink: \(ink)px @thr0.88")
        // 对照：旧 hairline（#EEEEF0）在同阈下测不到
        let hairlineReplica = render(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .background(Color.white)
        )
        let hairlineInk = hairlineReplica.inkCount(
            x: 0...22, y: 0...22, threshold: 0.88
        )
        XCTAssertLessThan(
            hairlineInk, 40,
            "hairline 对照应近乎测不到（实测 \(hairlineInk)px）"
        )
    }

    // MARK: - ③④⑤ 行：顶差/摘要 pitch/行 pitch

    private func sampleRow(store: GoalsStore) -> GoalRowView {
        let goal = BridgeGoal(
            id: "g478", title: "把家庭网络巡检做成长期机制",
            note: "", createdAt: 0, updatedAt: 0, status: .active
        )
        return GoalRowView(
            store: store, goal: goal,
            summary: "家庭网络每小时巡检完成一轮：NAS、主路由、旁路由、Open-Box、实测代理、VRRP、WireGuard 与 DDNS 全部正常，番茄广告 DNS 过滤生效，本轮无异常需要处理。",
            acting: false,
            onToggleStatus: {}, onEdit: {}, onDelete: {}
        )
    }

    func testRowGeometryMatchesReference() throws {
        let store = GoalsStore()
        // 行宽＝屏宽 402 − 左右 pageGutter 20×2＝362
        // （与真机帧同位）；两行同组间距＝组内距
        // spacingM（§485 pitch 合成口径，与
        // GoalsView.goalGroup 同值）
        let stack = VStack(spacing: OneDayMetrics.spacingM) {
            sampleRow(store: store)
            sampleRow(store: store)
        }
        .frame(width: 362)
        .background(Color.white)
        let bmp = render(stack)

        // ③ 框顶 vs 标题首行顶（行内坐标：框列
        // x<28、标题列 x 32...300；框墨迹阈 0.88；
        // 标题墨迹阈 0.30——标题 bodyInk 亮度
        // ≈0.1、摘要 inkSecondary ≈0.43，0.30 阈
        // 把两者分开，防第二行搜索误触摘要行）
        let cbTop = try XCTUnwrap(
            bmp.firstInkRow(fromY: 0, x: 0...28, threshold: 0.88),
            "第一行复选框墨迹未测到"
        )
        let titleTop1 = try XCTUnwrap(
            bmp.firstInkRow(fromY: 0, x: 32...300, threshold: 0.30),
            "第一行标题墨迹未测到"
        )
        XCTAssertLessThanOrEqual(
            abs(cbTop - titleTop1), 3,
            "框顶 \(cbTop) 与标题顶 \(titleTop1) 差应 ≤3pt"
        )
        print("MEASURE478 tops: cb=\(cbTop) title=\(titleTop1)")

        // ④ 摘要行 pitch：标题行盒（25pt）以下找墨
        // 迹带（阈 0.75、x 同标题列），带中心距应
        // 19±1.5 且恰 3 带（lineLimit 3）
        let summaryTop = titleTop1 + 24
        var bandCenters: [CGFloat] = []
        var y = summaryTop
        var inBand = false
        var bandStart: CGFloat = 0
        while y < titleTop1 + 90 {
            let hasInk = bmp.inkCount(
                x: 32...300, y: y...(y + 0.99), threshold: 0.75
            ) >= 4
            if hasInk, !inBand {
                inBand = true
                bandStart = y
            } else if !hasInk, inBand {
                inBand = false
                bandCenters.append((bandStart + y - 1) / 2)
            }
            y += 1
        }
        if inBand { bandCenters.append((bandStart + y - 1) / 2) }
        XCTAssertEqual(
            bandCenters.count, 3,
            "摘要应恰 3 行（实测带 \(bandCenters)）"
        )
        print("MEASURE478 summary band centers: \(bandCenters)")
        if bandCenters.count == 3 {
            for i in 1...2 {
                let pitch = bandCenters[i] - bandCenters[i - 1]
                XCTAssertEqual(
                    pitch, 19, accuracy: 1.5,
                    "摘要行 pitch 应 19±1（实测 \(pitch)）"
                )
            }
        }

        // ⑤ 行 pitch：第二行标题顶 − 第一行标题顶
        // （阈 0.30 同 ③，只认标题级深墨）
        let titleTop2 = try XCTUnwrap(
            bmp.firstInkRow(
                fromY: titleTop1 + 70, x: 32...300,
                threshold: 0.30
            ),
            "第二行标题墨迹未测到"
        )
        let rowPitch = titleTop2 - titleTop1
        XCTAssertEqual(
            rowPitch, 102, accuracy: 6,
            "行 pitch 应 102±6（实测 \(rowPitch)）"
        )
        print("MEASURE478 row pitch: \(rowPitch)")
    }

    // MARK: - 附：页题档与段头形态旁证

    func testPageTitleInkMatches24ptTier() {
        let bmp = render(GoalsPageTitle().background(Color.white))
        // 「目标」两字 24pt 粗体墨迹高 ≈22（参照帧
        // 实测 22.0）；宽 ≈46–48
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var ink = 0
        for py in 0..<bmp.pxHeight {
            for px in 0..<bmp.pxWidth
            where bmp.luminance(pxX: px, pxY: py) < 0.5 {
                ink += 1
                minY = min(minY, CGFloat(py) / 3)
                maxY = max(maxY, CGFloat(py) / 3)
            }
        }
        XCTAssertGreaterThan(ink, 100)
        let inkHeight = maxY - minY + 1.0 / 3.0
        print("MEASURE478 page title ink height: \(inkHeight)")
        XCTAssertEqual(
            inkHeight, 22, accuracy: 2,
            "页题墨迹高应 ≈22（实测 \(inkHeight)）"
        )
    }

    func testGroupHeaderHasNoTintPlate() {
        let bmp = render(
            GoalGroupHeader(title: "追踪", completed: false)
                .background(Color.white)
        )
        // 无底盘：旧底盘是 Ø17 圆、盖住点右
        // 11.5–17.5pt 带；新形态该带只有 Ø10 点
        // 的抗锯齿边（首跑全帧计 150px 皆点边羽
        // 化）——只查该带内的浅绿盘色（tintGreen
        // #E3F3E8 的特征＝三通道皆 >0.85 且
        // G>R），带内应近乎为零
        var platePx = 0
        let bandX0 = Int(11.5 * 3)
        let bandX1 = Int(17.5 * 3)
        for py in 0..<bmp.pxHeight {
            for px in bandX0...bandX1 {
                let i = (py * bmp.pxWidth + px) * 4
                let r = Double(bmp.rgba[i]) / 255.0
                let g = Double(bmp.rgba[i + 1]) / 255.0
                let b = Double(bmp.rgba[i + 2]) / 255.0
                if r > 0.85, g > 0.85, b > 0.85, g > r {
                    platePx += 1
                }
            }
        }
        XCTAssertLessThan(
            platePx, 10, "段头点右带内不应有浅绿底盘（实测 \(platePx)px）"
        )
        // 绿点在位：饱和绿像素应成量（Ø10 圆
        // ≈78pt²、@3x 约 700px，取下限 200）
        var greenPx = 0
        for py in 0..<bmp.pxHeight {
            for px in 0..<bmp.pxWidth {
                let i = (py * bmp.pxWidth + px) * 4
                let r = Double(bmp.rgba[i]) / 255.0
                let g = Double(bmp.rgba[i + 1]) / 255.0
                if g > 0.45, g > r + 0.12 {
                    greenPx += 1
                }
            }
        }
        XCTAssertGreaterThan(
            greenPx, 200, "状态绿点应可测（实测 \(greenPx)px）"
        )
    }
}
