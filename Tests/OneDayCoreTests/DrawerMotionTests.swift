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
        // 恰在阈值上不算 fling（落到位置段：10 未过半 → 维持合）
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 10, startOffset: 0, predictedExtra: 0,
                velocityX: 800, travel: travel
            )
        )
    }

    // MARK: - §323 落定两段式（Proton 预测增量守卫）

    func testSettleGuardTierTrustsPredictedEndSign() {
        // 守卫带钉值：25pt（Proton 设计事实）
        XCTAssertEqual(DrawerMotion.predictionGuard, 25)
        // 拖 60（未过半）＋预测增量 40（过守卫带）：
        // 预测终点相对接管起点 +100、在开侧 → 开
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 60, startOffset: 0, predictedExtra: 40,
                velocityX: 0, travel: travel
            )
        )
        // 预测增量 30（刚过守卫带）：预测终点 +90 在
        // 开侧 → 开——§323 前的 30% 口径下 90<96 判
        // 合，本段起改判（甩动有效即信预测终点、不
        // 再叠位移阈值，Proton 同式）
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 60, startOffset: 0, predictedExtra: 30,
                velocityX: 0, travel: travel
            )
        )
        // 开态起反向：拖回 60＋预测增量 −50 → 预测终
        // 点相对起点 −110、在合侧 → 关
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 260, startOffset: 320, predictedExtra: -50,
                velocityX: 0, travel: travel
            )
        )
        // 符号原点是接管起点：开态小拖回 20＋往开侧
        // 甩（增量 +30）→ 预测终点 +10 在开侧 → 开
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 300, startOffset: 320, predictedExtra: 30,
                velocityX: 0, travel: travel
            )
        )
    }

    func testSettlePositionTierWhenPredictionInsignificant() {
        // 增量恰 25（守卫带内、含界）不认甩动：拖 60
        // 未过半 → 合（增量不进判定）
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 60, startOffset: 0, predictedExtra: 25,
                velocityX: 0, travel: travel
            )
        )
        // 慢拖过半（200/320）＋带内增量 −20 → 开（位
        // 置说了算、反向小增量不翻盘）
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 200, startOffset: 0, predictedExtra: -20,
                velocityX: 0, travel: travel
            )
        )
        // 开态慢拖回 260（仍过半）＋增量 −20 → 维持开
        XCTAssertTrue(
            DrawerMotion.settleOpens(
                currentOffset: 260, startOffset: 320, predictedExtra: -20,
                velocityX: 0, travel: travel
            )
        )
        // 恰半程不算过半（Proton 同式、严格大于）
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 160, startOffset: 0, predictedExtra: 0,
                velocityX: 0, travel: travel
            )
        )
        // travel 未量得（0）保守合（两段同归）
        XCTAssertFalse(
            DrawerMotion.settleOpens(
                currentOffset: 100, startOffset: 0, predictedExtra: 100,
                velocityX: 0, travel: 0
            )
        )
    }

    // MARK: - §323 场景门（学 Simplenote C/D/F）

    func testSceneGateBlocksEachConditionIndependently() {
        let clear = DrawerMotion.GestureScene(
            contentListDragging: false, drawerListDragging: false,
            contentNavigationDepth: 1, isEditing: false
        )
        XCTAssertTrue(DrawerMotion.allowsOpenGesture(scene: clear))
        // 门 C 两半：任一侧列表 dragging 中即挡
        var scene = clear
        scene.contentListDragging = true
        XCTAssertFalse(DrawerMotion.allowsOpenGesture(scene: scene))
        scene = clear
        scene.drawerListDragging = true
        XCTAssertFalse(DrawerMotion.allowsOpenGesture(scene: scene))
        // 门 D：深度 2 起挡；根层 1 与退化值 0 不挡
        scene = clear
        scene.contentNavigationDepth = 2
        XCTAssertFalse(DrawerMotion.allowsOpenGesture(scene: scene))
        scene = clear
        scene.contentNavigationDepth = 0
        XCTAssertTrue(DrawerMotion.allowsOpenGesture(scene: scene))
        // 门 F：编辑态挡
        scene = clear
        scene.isEditing = true
        XCTAssertFalse(DrawerMotion.allowsOpenGesture(scene: scene))
        // 三门同命中仍是挡（无优先级分叉）
        scene = DrawerMotion.GestureScene(
            contentListDragging: true, drawerListDragging: true,
            contentNavigationDepth: 3, isEditing: true
        )
        XCTAssertFalse(DrawerMotion.allowsOpenGesture(scene: scene))
    }

    // MARK: - §323 裁切几何派生单源（迁入 DrawerMotion）

    func testClipGeometryDerivesFromProgress() {
        let size = CGSize(width: 393, height: 852)
        // 合态：全幅、无内嵌、半径 0
        let closed = DrawerMotion.clipGeometry(
            progress: 0, foregroundSize: size)
        XCTAssertEqual(closed.clipFrame, CGRect(x: 0, y: 0, width: 393, height: 852))
        XCTAssertEqual(closed.contentFrame, CGRect(x: 0, y: 0, width: 393, height: 852))
        XCTAssertEqual(closed.radius, 0)
        // 开态：纵向内嵌 2、内容反向补偿（原点 −2、
        // 高不变）、半径 54.5
        let open = DrawerMotion.clipGeometry(
            progress: 1, foregroundSize: size)
        XCTAssertEqual(open.clipFrame, CGRect(x: 0, y: 2, width: 393, height: 848))
        XCTAssertEqual(open.contentFrame, CGRect(x: 0, y: -2, width: 393, height: 852))
        XCTAssertEqual(open.radius, 54.5)
        // 中途：内嵌随 progress 线性（0.5 → 1）、半
        // 径已一步到位
        let mid = DrawerMotion.clipGeometry(
            progress: 0.5, foregroundSize: size)
        XCTAssertEqual(mid.clipFrame.origin.y, 1, accuracy: 0.001)
        XCTAssertEqual(mid.contentFrame.origin.y, -1, accuracy: 0.001)
        XCTAssertEqual(mid.radius, 54.5)
        // 与分件派生逐值一致（迁入不改值：半径/内嵌
        // 与 cornerRadius/verticalInset 同源）
        for p: CGFloat in [0, 0.01, 0.5, 1, 2] {
            let geometry = DrawerMotion.clipGeometry(
                progress: p, foregroundSize: size)
            XCTAssertEqual(geometry.radius, DrawerMotion.cornerRadius(progress: p))
            XCTAssertEqual(
                geometry.clipFrame.origin.y,
                DrawerMotion.verticalInset(progress: p),
                accuracy: 0.001)
        }
    }

    // MARK: - S3/§3.4 白名单定值（§202 换代）

    func testCornerRadiusStepsOnceAndShadowValuesAreFixed() {
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.02), 0)
        // 过阈一步到 54.5（§202 量测 Muse 新参照拟合
        // 定值），之后恒定（拖动期不插值，K4）
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.021), 54.5)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 0.5), 54.5)
        XCTAssertEqual(DrawerMotion.cornerRadius(progress: 1), 54.5)
        // §202 柔影回宽定值：radius 18／x −4／峰值 0.22
        XCTAssertEqual(DrawerMotion.shadowRadius, 18)
        XCTAssertEqual(DrawerMotion.shadowX, -4)
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 1), 0.22)
        XCTAssertEqual(
            DrawerMotion.shadowOpacity(progress: 0.5), 0.11, accuracy: 0.0001
        )
        // 越界进度钳制，不放大阴影
        XCTAssertEqual(DrawerMotion.shadowOpacity(progress: 2), 0.22)
    }

    // MARK: - §202 K1 纵向内嵌

    func testVerticalInsetIsLinearClamped() {
        XCTAssertEqual(DrawerMotion.cardVerticalInset, 2)
        XCTAssertEqual(DrawerMotion.verticalInset(progress: 0), 0)
        XCTAssertEqual(DrawerMotion.verticalInset(progress: 0.5), 1)
        XCTAssertEqual(DrawerMotion.verticalInset(progress: 1), 2)
        // 越界钳制（橡皮筋段不放大内嵌）
        XCTAssertEqual(DrawerMotion.verticalInset(progress: 2), 2)
        XCTAssertEqual(DrawerMotion.verticalInset(progress: -1), 0)
    }

    // MARK: - §351 刚体派生（横向内缩＋纵向 scale 等效）

    func testCardLeadingShiftDarkOnlyLinearClamped() {
        XCTAssertEqual(DrawerCardGeometry.darkCardLeadingInset, 16)
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 0, appearance: .dark), 0)
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 0.5, appearance: .dark), 8)
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 1, appearance: .dark), 16)
        // 越界钳制（橡皮筋段不放大内缩）
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 2, appearance: .dark), 16)
        // 浅色恒 0（无中间层、接缝走 §345 柔影）
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 0.5, appearance: .light), 0)
        XCTAssertEqual(
            DrawerMotion.cardLeadingShift(progress: 1, appearance: .light), 0)
    }

    /// scaleY 等效与旧帧几何逐值一致：卡面纵向跨
    /// 度（H×scaleY）＝旧 clip 帧高、上下沿留白
    /// （(H−H×scaleY)/2）＝旧 clip 帧原点 y
    func testCardScaleYMatchesClipGeometryEquivalence() {
        for height: CGFloat in [852, 393, 874] {
            for p: CGFloat in [0, 0.5, 1, 2] {
                let scale = DrawerMotion.cardScaleY(
                    progress: p, foregroundHeight: height)
                let geometry = DrawerMotion.clipGeometry(
                    progress: p,
                    foregroundSize: CGSize(width: 393, height: height))
                XCTAssertEqual(
                    height * scale, geometry.clipFrame.height,
                    accuracy: 0.001)
                XCTAssertEqual(
                    (height - height * scale) / 2,
                    geometry.clipFrame.origin.y,
                    accuracy: 0.001)
            }
        }
        // 高度未量得时恒 1（不缩放）
        XCTAssertEqual(
            DrawerMotion.cardScaleY(progress: 1, foregroundHeight: 0), 1)
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

    // MARK: - §313 几何单源转发（横扫 A-02）

    func testGeometryConstantsForwardFromSingleSource() {
        // DrawerMotion 白名单与 DrawerCardGeometry 单
        // 源逐项同值——任一处私改一值即红
        XCTAssertEqual(
            DrawerMotion.cardCornerRadius,
            DrawerCardGeometry.cornerRadius
        )
        XCTAssertEqual(
            DrawerMotion.cardVerticalInset,
            DrawerCardGeometry.verticalInset
        )
        XCTAssertEqual(
            DrawerMotion.cornerStepProgress,
            DrawerCardGeometry.cornerStepProgress
        )
        XCTAssertEqual(DrawerMotion.shadowRadius, DrawerCardGeometry.shadowRadius)
        XCTAssertEqual(DrawerMotion.shadowX, DrawerCardGeometry.shadowX)
        XCTAssertEqual(
            DrawerMotion.shadowMaxOpacity,
            DrawerCardGeometry.shadowMaxOpacity
        )
        // 推开量派生：宽×0.79、无 cap（2026-11-21 样
        // 板对齐包改值，现行版 Muse 截图实测占比，
        // 见 DrawerCardGeometry.travelWidthFraction 注）
        XCTAssertEqual(DrawerCardGeometry.travel(containerWidth: 402), 317.58, accuracy: 0.001)
        XCTAssertEqual(DrawerCardGeometry.travel(containerWidth: 393), 310.47, accuracy: 0.001)
        XCTAssertEqual(DrawerCardGeometry.travel(containerWidth: 0), 0)
    }

    // MARK: - §313 锁步派生（第 78 条 D1）

    func testDrawerOffsetLockstepsWithForeground() {
        // 合态：抽屉整体左移一个 travel 藏于主面之后
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 0, travel: travel), -320)
        // 开态：抽屉归位 0
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 320, travel: travel), 0)
        // 中途：与主面同刚体（位移差恒为 travel）
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 160, travel: travel), -160)
        // travel 未量得：抽屉不动
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 0, travel: 0), 0)
    }

    /// §318 越界钳制（诊断 F2）：§313「橡皮筋越界不
    /// 钳制、双层同量越界」在真机录屏实证露底（开向
    /// 过冲抽屉左缘离屏左约 52pt 露容器底色），自此
    /// 越界段钳制到 [−travel, 0]、界内公式不变（界
    /// 内逐值由上例把守）
    func testDrawerOffsetClampsOvershootToPanelBounds() {
        // 开向过冲：抽屉钉死 0、面板左缘不离屏左
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 400, travel: travel), 0)
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 320.5, travel: travel), 0)
        // 关向过冲：抽屉停在 −travel、整份藏好不深追
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: -30, travel: travel), -320)
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: -400, travel: travel), -320)
        // travel 未量得：任何 offset 恒 0（容器「未量
        // 得不动」口径的结构性成立）
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: 100, travel: 0), 0)
        XCTAssertEqual(DrawerMotion.drawerOffset(offset: -100, travel: 0), 0)
    }

    // MARK: - §313 阴影外观口径（第 78 条 D4）

    func testShadowOpacityDarkAppearanceIsZero() {
        // 深色恒 0（Muse 深色帧段无可量测阴影）
        XCTAssertEqual(
            DrawerMotion.shadowOpacity(progress: 1, appearance: .dark), 0
        )
        XCTAssertEqual(
            DrawerMotion.shadowOpacity(progress: 0.5, appearance: .dark), 0
        )
        // 浅色与无参口径逐值一致（S3 老口径不分叉）
        for p: CGFloat in [0, 0.25, 0.5, 1, 2] {
            XCTAssertEqual(
                DrawerMotion.shadowOpacity(progress: p, appearance: .light),
                DrawerMotion.shadowOpacity(progress: p),
                accuracy: 0.0001
            )
        }
    }
}
