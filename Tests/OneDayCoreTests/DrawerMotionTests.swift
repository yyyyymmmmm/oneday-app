import OneDayCore
import XCTest

/// 抽屉动效纯逻辑（0.7.1，chrome 裁决档 §3.5 S1–S8）：
/// 方向锁定、跟手换算、松手吸附与白名单定值逐项钉死
/// ——0.6.1 真机「滑动不流畅、页面卡变形」的六条定因
/// （§1.5）不许在逻辑层回归
final class DrawerMotionTests: XCTestCase {
    private let travel: CGFloat = 320

    // MARK: - S2 方向锁定

    func testDirectionLockRequiresDistanceAndDominance() {
        // 未达 10pt：不接管（纵滚头几毫米零干扰）
        XCTAssertFalse(DrawerMotion.isDirectionLocked(dx: 9.9, dy: 0))
        XCTAssertFalse(DrawerMotion.isDirectionLocked(dx: -9.9, dy: 0))
        // 达距但横向不主导（|dx| < 1.5|dy|）：不接管
        XCTAssertFalse(DrawerMotion.isDirectionLocked(dx: 14, dy: 10))
        // 达距且主导：接管（双向同判）
        XCTAssertTrue(DrawerMotion.isDirectionLocked(dx: 10, dy: 0))
        XCTAssertTrue(DrawerMotion.isDirectionLocked(dx: 15, dy: 10))
        XCTAssertTrue(DrawerMotion.isDirectionLocked(dx: -15, dy: 10))
    }

    // MARK: - S1 派生

    func testProgressClampsAndIsOpenDerivesFromOffset() {
        XCTAssertEqual(DrawerMotion.progress(offset: 0, travel: travel), 0)
        XCTAssertEqual(DrawerMotion.progress(offset: 160, travel: travel), 0.5)
        XCTAssertEqual(DrawerMotion.progress(offset: 320, travel: travel), 1)
        // 橡皮筋越界段不放大进度
        XCTAssertEqual(DrawerMotion.progress(offset: 400, travel: travel), 1)
        XCTAssertEqual(DrawerMotion.progress(offset: -30, travel: travel), 0)
        XCTAssertEqual(DrawerMotion.progress(offset: 10, travel: 0), 0)
        XCTAssertFalse(DrawerMotion.isOpen(offset: 160, travel: travel))
        XCTAssertTrue(DrawerMotion.isOpen(offset: 161, travel: travel))
        XCTAssertFalse(DrawerMotion.isOpen(offset: 300, travel: 0))
    }

    // MARK: - S2 跟手换算（扣锁定段）

    func testFollowedOffsetDeductsLockSegment() {
        // 接管时手势已走 12pt、卡在 0：其后手势到 112，
        // 卡只走 100——锁定段不写入，起步无跳（§1.5-5）
        XCTAssertEqual(
            DrawerMotion.followedOffset(
                startOffset: 0, translation: 12, lockTranslation: 12,
                travel: travel
            ), 0
        )
        XCTAssertEqual(
            DrawerMotion.followedOffset(
                startOffset: 0, translation: 112, lockTranslation: 12,
                travel: travel
            ), 100
        )
        // 开态关拖同式
        XCTAssertEqual(
            DrawerMotion.followedOffset(
                startOffset: 320, translation: -52, lockTranslation: -12,
                travel: travel
            ), 280
        )
    }

    func testFollowedOffsetRubberBandsBeyondBounds() {
        // 越过全开位：超出段走橡皮筋（渐进衰减、小于原量）
        let over = DrawerMotion.followedOffset(
            startOffset: 320, translation: 120, lockTranslation: 20,
            travel: travel
        )
        XCTAssertGreaterThan(over, 320)
        XCTAssertLessThan(over, 420)
        // 越过合拢位：负向同理
        let under = DrawerMotion.followedOffset(
            startOffset: 0, translation: -120, lockTranslation: -20,
            travel: travel
        )
        XCTAssertLessThan(under, 0)
        XCTAssertGreaterThan(under, -100)
        // 界内严格 1:1
        XCTAssertEqual(
            DrawerMotion.followedOffset(
                startOffset: 100, translation: 30, lockTranslation: 10,
                travel: travel
            ), 120
        )
    }

    // MARK: - S6 松手吸附

    func testSettleFlingOverridesPosition() {
        // 几乎没拖动，高速右甩 → 直通开
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 10, startOffset: 0, predictedExtra: 0,
                velocityX: 801, travel: travel
            )
        )
        // 已拖过半，高速左甩 → 直通关
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 300, startOffset: 320, predictedExtra: 0,
                velocityX: -801, travel: travel
            )
        )
        // 恰在阈值上不算 fling（走位置判定：相对偏移小 → 维持合）
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 10, startOffset: 0, predictedExtra: 0,
                velocityX: 800, travel: travel
            )
        )
    }

    func testSettlePredictedProjectionThirtyPercent() {
        // 合态起：当前偏移＋动量外推过 30% travel（96）→ 开
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 60, startOffset: 0, predictedExtra: 40,
                velocityX: 0, travel: travel
            )
        )
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 60, startOffset: 0, predictedExtra: 30,
                velocityX: 0, travel: travel
            )
        )
        // 开态起：反向偏移未过 −30% → 维持开；过 → 关
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 260, startOffset: 320, predictedExtra: -20,
                velocityX: 0, travel: travel
            )
        )
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 260, startOffset: 320, predictedExtra: -50,
                velocityX: 0, travel: travel
            )
        )
        // travel 未量得（0）保守合
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 100, startOffset: 0, predictedExtra: 100,
                velocityX: 0, travel: 0
            )
        )
    }

    // MARK: - S3/§3.4 白名单定值

    func testCornerRadiusStepsOnceAndShadowValuesAreFixed() {
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.02), 0)
        // 过阈一步到 43（§179.2 量测 Muse 参照定值），
        // 之后恒定（拖动期不插值）
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.021), 43)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.5), 43)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 1), 43)
        // §3.4 柔影定值：radius 10／x −4／峰值 alpha 0.12
        XCTAssertEqual(DrawerMotion.shadowRadius, 10)
        XCTAssertEqual(DrawerMotion.shadowX, -4)
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 1), 0.12)
        XCTAssertEqual(
            DrawerMotion.shadowOpacity(progress: 0.5), 0.06, accuracy: 0.0001
        )
        // 越界进度钳制，不放大阴影
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 2), 0.12)
    }

    // MARK: - 0.17.0 覆盖形态蒙层

    func testScrimOpacityIsLinearClampedAndMonotonic() {
        XCTAssertEqual(DrawerMotion.scrimMaxOpacity, 0.32)
        XCTAssertEqual(DrawerMotion.scrimOpacity(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.scrimOpacity(progress: 1), 0.32)
        XCTAssertEqual(
            DrawerMotion.scrimOpacity(progress: 0.5), 0.16, accuracy: 0.0001
        )
        XCTAssertEqual(
            DrawerMotion.scrimOpacity(progress: 0.25), 0.08, accuracy: 0.0001
        )
        // 橡皮筋越界与负进度钳制，不放大也不出负
        XCTAssertEqual(DrawerMotion.scrimOpacity(progress: 2), 0.32)
        XCTAssertEqual(DrawerMotion.scrimOpacity(progress: -0.5), 0)
        // 全程单调不减（拖动中蒙层不许忽深忽浅）
        var previous = -1.0
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = DrawerMotion.scrimOpacity(progress: CGFloat(step))
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }
}
