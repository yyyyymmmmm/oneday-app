import Foundation

/// 图片查看器纯逻辑（0.36.4，体验三件规格 §3）：双态
/// （卡态/沉浸）＋集合分页的状态机。视图层（Image-
/// ViewerView）只持本状态、按它渲染——索引夹紧、切
/// 页清缩放、放大禁翻页、chrome 显隐全在此裁决，
/// 单测钉死防回潮（转场与手势本体走系统机制、不在
/// 本面）。

/// 查看器双态：卡态＝默认态（页面底、图成卡、chrome
/// 在场）；沉浸态＝点图切换（黑底全幅、chrome 隐）
public enum ImageViewerMode: Equatable, Sendable {
    case card
    case immersive
}

public struct ImageViewerState: Equatable, Sendable {
    /// 集合总数（≤0 时查看器无可显示、索引恒 0）
    public let count: Int
    /// 当前页索引（恒夹在 0…count−1；空集恒 0）
    public private(set) var index: Int
    /// 当前双态
    public private(set) var mode: ImageViewerMode
    /// 当前页是否处于放大态（>1×；放大时禁翻页——
    /// 平移看图优先于翻页，规格 §3.4）
    public private(set) var isZoomed: Bool

    public init(count: Int, initialIndex: Int) {
        self.count = max(count, 0)
        self.index = Self.clamped(initialIndex, count: self.count)
        self.mode = .card
        self.isZoomed = false
    }

    /// 索引夹紧：空集恒 0、负数归 0、越界归末页
    public static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    /// 翻页（分页控件回写）：夹紧落位；换页即清放大
    /// 态（新页从 1× 起，前页的缩放不许带过来）
    public mutating func select(index newIndex: Int) {
        let target = Self.clamped(newIndex, count: count)
        if target != index {
            index = target
            isZoomed = false
        }
    }

    /// 点图切双态（卡↔沉浸往返）；切回卡态时清放大
    /// 态（卡面恒 1× 呈现，与 Muse 卡态口径一致）
    public mutating func toggleMode() {
        mode = (mode == .card) ? .immersive : .card
        if mode == .card {
            isZoomed = false
        }
    }

    /// 缩放态回写（ZoomableImageView 的 isZoomed 通道）
    public mutating func setZoomed(_ zoomed: Bool) {
        isZoomed = zoomed
    }

    /// 翻页可用性：放大态禁翻页（外层分页滚动据此
    /// scrollDisabled，内层图面平移不受影响）
    public var pagingEnabled: Bool { !isZoomed }

    /// chrome（关闭钮＋工具胶囊）显隐：只在卡态在场，
    /// 沉浸态全隐（规格 §3.1 实证：工具栏俱隐）
    public var chromeVisible: Bool { mode == .card }

    /// 是否有可显示内容
    public var hasContent: Bool { count > 0 }
}

/// 卡态图面 fitted 尺寸（0.36.4）：图按自身宽高比
/// 完整装入给定的最大宽高内、不放大（小图按原尺
/// 寸）——卡的形状即图的形状（规格 §3.1：图按宽
/// 高比完整装入卡内）。非法图尺寸（≤0）回落为最
/// 大宽高的一半方幅，不产出零尺寸。
public enum ImageViewerLayout {
    public static func fittedSize(
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> CGSize {
        guard imageWidth > 0, imageHeight > 0,
              maxWidth > 0, maxHeight > 0 else {
            let side = max(min(maxWidth, maxHeight), 0)
            return CGSize(width: side, height: side)
        }
        let scale = min(
            maxWidth / imageWidth,
            maxHeight / imageHeight,
            1
        )
        return CGSize(
            width: imageWidth * scale,
            height: imageHeight * scale
        )
    }
}
