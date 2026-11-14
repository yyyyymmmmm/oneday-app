import OneDayDesign
import SwiftUI
import UIKit
import XCTest
@testable import OneDayApp

/// §224 守护（头像呈现 harmonize）：用户 2026-11-14
/// 真机点名预置爪印头像「样式和大小不对劲、不匹配」
/// ——病灶三处：页头盘 110 偏大、符号字形只占盘约
/// 42% 浮在自调 pastel 大色盘中央、各位点尺寸散值。
/// 本测钉住收敛后的呈现契约：尺寸三档令牌值、字形
/// 占盘比、离屏渲染实测的字形跨度与盘面中性（蓝偏
/// 回归即红）。
@MainActor
final class AvatarPresentationFitTests: XCTestCase {

    func testAvatarSizeTierTokens() {
        XCTAssertEqual(OneDayMetrics.avatarPageHead, 90)
        XCTAssertEqual(OneDayMetrics.avatarSectionHead, 45)
        XCTAssertEqual(OneDayMetrics.avatarListRow, 44)
    }

    func testPresetDiscGlyphRatio() {
        XCTAssertEqual(
            AgentAvatarPresetDisc.glyphRatio, 0.92, accuracy: 0.001
        )
    }

    /// 离屏渲染 240 盘实测：中心行上字形墨跨度/盘跨
    /// 度须至少为 0.75；盘面
    /// 取样点须冷中性（蓝−红差 ≤8；旧 tintSky #EDF7FD
    /// 的蓝偏为 16、在此红）。
    func testRenderedPresetDiscGlyphSpanAndNeutralFill() throws {
        let content = ZStack {
            Color.white
            AgentAvatarPresetDisc(
                symbolName: "pawprint.fill",
                tint: AgentProfileStore.presetTint(id: "paw"),
                diameter: 240
            )
        }
        .frame(width: 240, height: 240)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let pixels = try XCTUnwrap(Self.rgbaPixels(of: image))
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        XCTAssertEqual(width, 240)
        XCTAssertEqual(height, 240)

        func pixel(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (
                Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])
            )
        }

        // 中心行扫描：盘跨度＝非白像素段，字形跨度＝
        // 深墨像素段（ink 浅档 #11191C，阈值取 110）
        let midY = height / 2
        var discSpan: (Int, Int)?
        var inkSpan: (Int, Int)?
        for x in 0..<width {
            let p = pixel(x, midY)
            if p.r < 248 || p.g < 248 || p.b < 248 {
                if discSpan == nil { discSpan = (x, x) }
                discSpan?.1 = x
            }
            if p.r < 110 && p.g < 110 && p.b < 110 {
                if inkSpan == nil { inkSpan = (x, x) }
                inkSpan?.1 = x
            }
        }
        let disc = try XCTUnwrap(discSpan, "盘面未渲染出")
        let ink = try XCTUnwrap(inkSpan, "字形未渲染出")
        let ratio = Double(ink.1 - ink.0 + 1) / Double(disc.1 - disc.0 + 1)
        XCTAssertTrue(
            ratio >= 0.75,
            "字形占盘比 \(ratio) 未达到 0.75"
        )

        // 在 r=105 的圆环上每 15° 取一点，选择最亮点作为
        // 盘面样本，避开可能覆盖边缘取样点的放大字形。
        let center = Double(width) / 2
        let ringRadius = 105.0
        let ringSamples = (0..<24).map { step -> (r: Int, g: Int, b: Int) in
            let angle = Double(step) * 15 * .pi / 180
            let x = Int((center + cos(angle) * ringRadius).rounded())
            let y = Int((center + sin(angle) * ringRadius).rounded())
            return pixel(x, y)
        }
        let sample = try XCTUnwrap(
            ringSamples.max { lhs, rhs in
                lhs.r + lhs.g + lhs.b < rhs.r + rhs.g + rhs.b
            }
        )
        XCTAssertTrue(
            (180...252).contains(sample.r),
            "盘面亮度异常：\(sample)"
        )
        XCTAssertLessThanOrEqual(
            abs(sample.b - sample.r), 8,
            "盘面带色偏（蓝−红=\(sample.b - sample.r)），非冷中性"
        )
    }

    private static func rgbaPixels(of image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width
        let height = cg.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &data, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
