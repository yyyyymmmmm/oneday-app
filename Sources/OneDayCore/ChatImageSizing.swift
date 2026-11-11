import Foundation

/// 已发送图片显示口径（§130，2026-11-11 用户双图
/// 点题改版）：由「fit-in-box 双封顶」改为**固定高
/// 度卡**。旧口径（0.36.19，§84.5）宽 220／高 240
/// 双封、等比缩进——图的呈现尺寸随原图比例变：
/// 竖长截图（宽高比约 1:2.17）缩成 110×240 的细
/// 长条，每张图高度都不一样；Muse 同一张图是统
/// 一卡片：高度固定、图完整装进卡内（用户 15:09
/// 附 OneDay 与 Muse 双图对比点名）。
///
/// 新口径（本枚举是已发图渲染的唯一尺寸口径：
/// 用户本地图 ChatView.bubble、远端图
/// ServerRemoteImage——用户与助手两侧共用）：
/// - 卡高恒定 190pt，不随图变；卡宽按图比例算
///   （卡高 × 宽高比），封顶 260pt、下限 96pt
/// - 图在卡内等比完整显示（fittedSize 给帧尺寸、
///   scaledToFit 语义）、不裁切；图比卡窄时两侧
///   露卡底色（bubbleFill，调用方承载），与
///   Muse 图中形态一致
/// - 只缩不放大：原图小于卡内可容纳尺寸时按原
///   尺寸显示（居中由调用方对齐），外层卡高仍
///   恒定
/// - 加载占位与失败态同卡高（190），消除旧占位
///   220×150 → 实际高度的跳变；占位时尚不知图
///   比例，卡宽取 cardPlaceholderWidth
/// - 入参同为 pt：调用方传 UIImage.size（已是
///   pt），不许传像素尺寸
/// - 非正尺寸（宽或高 ≤0）：卡回占位方卡、图帧
///   回 .zero——坏数据防御，不替渲染层拿主意
/// - 全屏查看器不走本口径（看原图是它的职责）
public enum ChatImageSizing {
    /// 卡高（恒定：所有已发图同高）
    public static let cardHeight: CGFloat = 190
    /// 卡宽封顶（横长图到此为止）
    public static let cardMaxWidth: CGFloat = 260
    /// 卡宽下限（竖长图不至于缩成细缝）
    public static let cardMinWidth: CGFloat = 96
    /// 比例未知时（加载占位／失败态）的卡宽
    public static let cardPlaceholderWidth: CGFloat = 190

    /// 卡的尺寸：高恒定、宽按图比例钳制
    public static func cardSize(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return placeholderCardSize
        }
        let width = cardHeight * imageSize.width / imageSize.height
        return CGSize(
            width: min(max(width, cardMinWidth), cardMaxWidth),
            height: cardHeight
        )
    }

    /// 图在卡内的显示帧：等比缩进卡内、只缩不放大
    public static func fittedSize(
        for imageSize: CGSize,
        in cardSize: CGSize
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return .zero
        }
        let scale = min(
            cardSize.width / imageSize.width,
            cardSize.height / imageSize.height,
            1
        )
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    /// 加载占位／失败态的卡尺寸（高度与正式卡一致）
    public static var placeholderCardSize: CGSize {
        CGSize(width: cardPlaceholderWidth, height: cardHeight)
    }
}
