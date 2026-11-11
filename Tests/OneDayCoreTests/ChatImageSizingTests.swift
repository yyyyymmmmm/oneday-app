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
}
