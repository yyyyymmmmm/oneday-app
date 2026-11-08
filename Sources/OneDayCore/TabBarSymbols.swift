import UIKit

/// 底栏字形（0.2.9 确定性路线，DESIGN-V4 §13）：SF Symbol
/// 以显式 pointSize 生成，字形高度由构造本身保证——先以
/// 参考尺寸（100pt）生成、量其 alpha 包围盒高，再按目标
/// 高线性定标 pointSize 重新生成。无画布、无留白缩放环
/// 节：成品图的字形高就是目标值本身。目标 24pt 对齐
/// Muse 底栏字形规格（用户口径「和 Muse 一样」）。
/// 定案凭据是单元测试（TabBarSymbolsTests）：以同一
/// alpha 量法断言四个字形高 24±2——测试绿即尺寸定案，
/// 与任何截图/渲染环境无关。
public enum TabBarSymbols {
    /// 目标字形高（pt）
    public static let glyphHeight: CGFloat = 24
    /// 四个底栏条目的系统符号名（与 ContentView 条目同序）
    public static let names = [
        "bubble.left.and.bubble.right",
        "chart.line.uptrend.xyaxis",
        "folder",
        "slider.horizontal.3",
    ]

    /// 四个条目的成品图预计算表（static let：构造一次、
    /// 并发安全；字形高 == glyphHeight，构造保证）
    private static let table: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        for name in names {
            result[name] = construct(named: name)
        }
        return result
    }()

    /// 按名取底栏图（表外名字按同一构造法即时生成）
    public static func image(named name: String) -> UIImage {
        table[name] ?? construct(named: name)
    }

    private static func construct(named name: String) -> UIImage {
        let reference = symbol(named: name, pointSize: 100)
        let referenceHeight = alphaBounds(of: reference).height
        if referenceHeight > 0 {
            return symbol(
                named: name,
                pointSize: 100 * glyphHeight / referenceHeight
            )
        }
        return reference
    }

    private static func symbol(
        named name: String, pointSize: CGFloat
    ) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: pointSize, weight: .regular
        )
        return (UIImage(systemName: name, withConfiguration: configuration)
            ?? UIImage()).withRenderingMode(.alwaysTemplate)
    }

    /// 图的 alpha 包围盒（pt）：位图化后逐像素扫 alpha≥16
    /// 的行列界。字形本体高度，与屏幕尺寸、底栏渲染环境
    /// 无关——这是「构造即定案」的量法本体，工厂定标与单
    /// 测断言共用同一份实现，不许各写一份。
    public static func alphaBounds(of image: UIImage) -> CGRect {
        let scale: CGFloat = 3
        let size = image.size
        guard size.width > 0, size.height > 0 else { return .zero }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let raster = UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(at: .zero) }
        guard let cgImage = raster.cgImage else { return .zero }
        let w = cgImage.width
        let h = cgImage.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let context = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .zero }
        context.draw(
            cgImage, in: CGRect(x: 0, y: 0, width: w, height: h)
        )
        var minRow = h, maxRow = -1, minCol = w, maxCol = -1
        for row in 0..<h {
            let rowBase = row * w * 4
            for col in 0..<w where pixels[rowBase + col * 4 + 3] >= 16 {
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
            }
        }
        guard maxRow >= 0 else { return .zero }
        return CGRect(
            x: CGFloat(minCol) / scale,
            y: CGFloat(minRow) / scale,
            width: CGFloat(maxCol - minCol + 1) / scale,
            height: CGFloat(maxRow - minRow + 1) / scale
        )
    }
}
