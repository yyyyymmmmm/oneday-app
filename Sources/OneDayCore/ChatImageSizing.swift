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
/// ServerRemoteImage——用户与助手两侧共用；
/// §150 起用户本地图多图成行走 rowCardSizes，
/// 仍在本枚举内收口）：
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

    /// 多图成行整行宽上限（§150）：用户气泡列在最
    /// 窄设备上的保守可用宽——单图封顶 260、双竖图
    /// 并排约 200 都在其内；整行超此宽才收窄（见
    /// rowCardSizes），不逐图单独钳制、保同高成行
    public static let multiRowMaxWidth: CGFloat = 320
    /// 多图成行卡间距（呈现层以 OneDayMetrics.
    /// spacingS 同值传入，拼装口径以本值为默认单源）
    public static let multiRowSpacing: CGFloat = 8
    /// 多图收窄时单卡宽下限：宁可整行略超上限，也
    /// 不把卡缩成细缝（极端多图/极端宽图保底）
    public static let multiRowMinCardWidth: CGFloat = 48

    /// 多图成行卡尺寸（§150，2026-11-11 用户 19:11
    /// 截图点题）：同一条消息的多张图并排成行、每张
    /// 一张固定高卡——对齐 Muse 多图用户消息形态
    /// （两张并排、同高卡片，用户截图实证）。口径：
    /// - 每张先按单图口径 cardSize 定卡（高恒定 190）
    /// - 整行宽（卡宽和＋(n−1)×间距）未超 maxRow-
    ///   Width 时原样返回——单张时与 cardSize 逐字
    ///   一致、零回归
    /// - 超宽时全行卡宽乘同一收窄系数（保各卡比例
    ///   关系）、卡高恒定不变；收窄后单卡宽不低于
    ///   multiRowMinCardWidth（保底优先于贴合，极
    ///   端时整行可略超上限）
    /// - 图在收窄卡内的帧仍走 fittedSize（等比完整
    ///   显示、居中露卡底），卡高不变故同行恒同高
    /// - 空数组回空数组
    public static func rowCardSizes(
        for imageSizes: [CGSize],
        maxRowWidth: CGFloat = multiRowMaxWidth,
        spacing: CGFloat = multiRowSpacing
    ) -> [CGSize] {
        let cards = imageSizes.map { cardSize(for: $0) }
        guard cards.count > 1 else { return cards }
        let spacingTotal = spacing * CGFloat(cards.count - 1)
        let widthTotal = cards.reduce(0) { $0 + $1.width }
        guard widthTotal + spacingTotal > maxRowWidth
        else { return cards }
        let scale = (maxRowWidth - spacingTotal) / widthTotal
        return cards.map { card in
            CGSize(
                width: max(card.width * scale, multiRowMinCardWidth),
                height: cardHeight
            )
        }
    }
}
