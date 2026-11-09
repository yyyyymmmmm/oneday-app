import UIKit
import XCTest

/// 0.22.0 一次性探针（定版后删除）：底栏 24pt 与抽屉
/// 27pt 两面的字形候选 × 字重（regular/light）墨迹密
/// 度量测，口径与 RenderMeasureTests 完全一致（紧致
/// alpha 包围盒＋44pt 格口径）。只 print MEASURE 行、
/// 不断言——选形与回填断言在读数后进行（审计 T1/D1
/// 要求：以 0.10–0.24 紧致密度带为选形带）。
final class GlyphProbeTests: XCTestCase {
    private struct InkStats {
        var density: Double
        var cellDensity: Double
        var tightWidthPt: CGFloat
        var tightHeightPt: CGFloat
    }

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

    private func probe(
        _ tag: String, _ name: String, size: CGFloat,
        weight: UIImage.SymbolWeight
    ) {
        guard let image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: size, weight: weight
            )
        ), let stats = analyze(image) else {
            print("MEASURE \(tag) \(name) FAILED")
            return
        }
        print(String(
            format: "MEASURE %@ %@ w=%@ density=%.3f cell=%.3f tight=%.1fx%.1fpt",
            tag, name, "\(weight.rawValue)",
            stats.density, stats.cellDensity,
            Double(stats.tightWidthPt), Double(stats.tightHeightPt)
        ))
    }

    func testGlyphProbe() {
        let candidates = [
            "message", "bubble.left", "lightbulb",
            "list.bullet", "checklist", "checkmark.square",
            "tray", "rectangle.stack",
        ]
        for name in candidates {
            probe("tab24", name, size: 24, weight: .regular)
            probe("tab24", name, size: 24, weight: .light)
            probe("drawer27", name, size: 27, weight: .regular)
            probe("drawer27", name, size: 27, weight: .light)
        }
        // 现行抽屉其余两件（主线聊天/管理）同面量测
        probe("drawer27", "checkmark", size: 27, weight: .regular)
        probe("drawer27", "checkmark", size: 27, weight: .light)
    }
}
