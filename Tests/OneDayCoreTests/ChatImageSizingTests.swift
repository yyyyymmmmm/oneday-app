import OneDayCore
import XCTest

/// 已发图固定高度卡尺寸（§130，2026-11-11 改版重
/// 写）：旧钉测对的是 0.36.19 fit-in-box 口径（宽
/// 220／高 240 双封、呈现尺寸随图比例变）——用户
/// 双图点题后定版为固定卡：卡高恒定 190、卡宽按
/// 比例钳制 [96, 260]、图在卡内等比完整显示只缩
/// 不放大。本文件按新口径整组重写，旧口径用例
/// （testVerticalScreenshotFitsByHeight 等 6 法）
/// 随口径作废，方法数 6 → 8 只增不减。入参按
/// pt 口径喂数（用例数值形状与真机截图同比例：
/// 竖长 1206×2622 即宽高比约 1:2.17 的手机截图）
final class ChatImageSizingTests: XCTestCase {

    func testVerticalScreenshotCardHitsMinWidth() {
        // 竖长图：比例算宽约 87.4 → 钳到下限 96；
        // 卡高恒定 190（旧口径同图为 110×240）
        let image = CGSize(width: 1206, height: 2622)
        let card = ChatImageSizing.cardSize(for: image)
        XCTAssertEqual(card.height, 190, accuracy: 0.01)
        XCTAssertEqual(card.width, 96, accuracy: 0.01)
        // 图在卡内以高定尺：87.4×190、完整不裁切、
        // 两侧露卡底（96 − 87.4 的余量）
        let fitted = ChatImageSizing.fittedSize(for: image, in: card)
        XCTAssertEqual(fitted.height, 190, accuracy: 0.01)
        XCTAssertEqual(fitted.width, 87.4, accuracy: 0.1)
    }

    func testHorizontalImageCardCappedAtMaxWidth() {
        // 横长图：比例算宽约 413 → 钳到封顶 260；
        // 图以宽定尺 260×119.6，上下露卡底
        let image = CGSize(width: 2622, height: 1206)
        let card = ChatImageSizing.cardSize(for: image)
        XCTAssertEqual(card.height, 190, accuracy: 0.01)
        XCTAssertEqual(card.width, 260, accuracy: 0.01)
        let fitted = ChatImageSizing.fittedSize(for: image, in: card)
        XCTAssertEqual(fitted.width, 260, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 119.6, accuracy: 0.1)
    }

    func testSquareImageCardIsSquare() {
        // 方图：卡 190×190，图恰好满卡
        let image = CGSize(width: 1000, height: 1000)
        let card = ChatImageSizing.cardSize(for: image)
        XCTAssertEqual(card.width, 190, accuracy: 0.01)
        XCTAssertEqual(card.height, 190, accuracy: 0.01)
        let fitted = ChatImageSizing.fittedSize(for: image, in: card)
        XCTAssertEqual(fitted.width, 190, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 190, accuracy: 0.01)
    }

    func testCardHeightIsConstantAcrossAspects() {
        // 任意比例卡高都是 190，且卡宽不出 [96, 260]
        let aspects: [CGSize] = [
            CGSize(width: 100, height: 3000),
            CGSize(width: 1206, height: 2622),
            CGSize(width: 1000, height: 1000),
            CGSize(width: 2622, height: 1206),
            CGSize(width: 4000, height: 500),
        ]
        for image in aspects {
            let card = ChatImageSizing.cardSize(for: image)
            XCTAssertEqual(card.height, ChatImageSizing.cardHeight)
            XCTAssertGreaterThanOrEqual(card.width, ChatImageSizing.cardMinWidth)
            XCTAssertLessThanOrEqual(card.width, ChatImageSizing.cardMaxWidth)
        }
    }

    func testSmallImageIsNotUpscaledButCardStaysFixed() {
        // 小图（100×80）：卡照常按比例 237.5×190，
        // 图按原尺寸不放大（居中由呈现层对齐）
        let image = CGSize(width: 100, height: 80)
        let card = ChatImageSizing.cardSize(for: image)
        XCTAssertEqual(card.width, 237.5, accuracy: 0.01)
        XCTAssertEqual(card.height, 190, accuracy: 0.01)
        let fitted = ChatImageSizing.fittedSize(for: image, in: card)
        XCTAssertEqual(fitted.width, 100, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 80, accuracy: 0.01)
    }

    func testExtremeThinImageCardStaysAtMinWidth() {
        // 极端细长：卡宽钳在下限 96 不成细缝，图
        // 以高定尺 6.3×190、完整显示
        let image = CGSize(width: 100, height: 3000)
        let card = ChatImageSizing.cardSize(for: image)
        XCTAssertEqual(card.width, 96, accuracy: 0.01)
        XCTAssertEqual(card.height, 190, accuracy: 0.01)
        let fitted = ChatImageSizing.fittedSize(for: image, in: card)
        XCTAssertEqual(fitted.height, 190, accuracy: 0.01)
        XCTAssertEqual(fitted.width, 6.3, accuracy: 0.1)
    }

    func testPlaceholderCardMatchesCardHeight() {
        // 加载占位／失败态：与正式卡同高（190），
        // 消除旧 220×150 占位 → 实际高度的跳变
        let placeholder = ChatImageSizing.placeholderCardSize
        XCTAssertEqual(placeholder.height, ChatImageSizing.cardHeight)
        XCTAssertEqual(placeholder.width, ChatImageSizing.cardPlaceholderWidth)
    }

    func testDegenerateSizeFallsBack() {
        // 非正尺寸：卡回占位方卡、图帧回 .zero
        // （防御口径，不替渲染层拿主意）
        let zero = CGSize(width: 0, height: 100)
        let card = ChatImageSizing.cardSize(for: zero)
        XCTAssertEqual(card, ChatImageSizing.placeholderCardSize)
        let fitted = ChatImageSizing.fittedSize(for: zero, in: card)
        XCTAssertEqual(fitted, .zero)
    }

    // MARK: - 多图成行（§150）

    func testRowCardSizesSingleImageMatchesCardSize() {
        // 单张：与 cardSize 逐字一致（零回归锚）
        let image = CGSize(width: 1206, height: 2622)
        let row = ChatImageSizing.rowCardSizes(for: [image])
        XCTAssertEqual(row.count, 1)
        XCTAssertEqual(row[0], ChatImageSizing.cardSize(for: image))
    }

    func testRowCardSizesTwoVerticalScreenshotsSideBySide() {
        // §150 主案（用户 19:09 选 2 张、19:11 实证
        // 只显 1 张）：两张竖长截图并排——出 2 张
        // 卡、同高 190、整行宽 96×2＋8＝200 不收窄
        let shot = CGSize(width: 1206, height: 2622)
        let row = ChatImageSizing.rowCardSizes(for: [shot, shot])
        XCTAssertEqual(row.count, 2)
        XCTAssertEqual(row[0].height, 190, accuracy: 0.01)
        XCTAssertEqual(row[1].height, 190, accuracy: 0.01)
        XCTAssertEqual(row[0].width, 96, accuracy: 0.01)
        XCTAssertEqual(row[1].width, 96, accuracy: 0.01)
        let total = row[0].width + row[1].width
            + ChatImageSizing.multiRowSpacing
        XCTAssertLessThanOrEqual(
            total, ChatImageSizing.multiRowMaxWidth
        )
        // 每张在卡内以高定尺完整显示（87.4×190）
        let fitted = ChatImageSizing.fittedSize(
            for: shot, in: row[0]
        )
        XCTAssertEqual(fitted.height, 190, accuracy: 0.01)
        XCTAssertEqual(fitted.width, 87.4, accuracy: 0.1)
    }

    func testRowCardSizesTwoWideImagesShrinkToFitRow() {
        // 两张横长图：单卡 260 → 整行 528 超 320，
        // 等比收窄到 (320−8)/2＝156、卡高恒定 190、
        // 两卡同宽（保比例同系数），整行恰贴上限
        let wide = CGSize(width: 2622, height: 1206)
        let row = ChatImageSizing.rowCardSizes(for: [wide, wide])
        XCTAssertEqual(row.count, 2)
        XCTAssertEqual(row[0].width, 156, accuracy: 0.01)
        XCTAssertEqual(row[1].width, 156, accuracy: 0.01)
        XCTAssertEqual(row[0].height, 190, accuracy: 0.01)
        XCTAssertEqual(row[1].height, 190, accuracy: 0.01)
        let total = row[0].width + row[1].width
            + ChatImageSizing.multiRowSpacing
        XCTAssertEqual(
            total, ChatImageSizing.multiRowMaxWidth, accuracy: 0.01
        )
        // 图在收窄卡内以宽定尺：156×71.7、上下露卡底
        let fitted = ChatImageSizing.fittedSize(
            for: wide, in: row[0]
        )
        XCTAssertEqual(fitted.width, 156, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 71.7, accuracy: 0.1)
    }

    func testRowCardSizesMixedAspectsKeepSameHeight() {
        // 混合比例（竖长＋方＋横长）：三卡同高
        // 190、整行贴上限、各卡宽按同一系数收窄
        let sizes = [
            CGSize(width: 1206, height: 2622),
            CGSize(width: 1000, height: 1000),
            CGSize(width: 2622, height: 1206),
        ]
        let row = ChatImageSizing.rowCardSizes(for: sizes)
        XCTAssertEqual(row.count, 3)
        for card in row {
            XCTAssertEqual(card.height, 190, accuracy: 0.01)
        }
        let total = row.reduce(0) { $0 + $1.width }
            + ChatImageSizing.multiRowSpacing * 2
        XCTAssertEqual(
            total, ChatImageSizing.multiRowMaxWidth, accuracy: 0.01
        )
        // 收窄系数同一：卡宽比＝单卡口径宽比
        // （96 : 190 : 260 同比缩放）
        XCTAssertEqual(
            row[1].width / row[0].width,
            190.0 / 96.0, accuracy: 0.01
        )
        XCTAssertEqual(
            row[2].width / row[0].width,
            260.0 / 96.0, accuracy: 0.01
        )
    }

    func testRowCardSizesEmptyInput() {
        // 空数组回空数组（无图消息不进成行口径）
        XCTAssertTrue(
            ChatImageSizing.rowCardSizes(for: []).isEmpty
        )
    }
}
