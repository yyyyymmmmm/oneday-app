import Foundation

/// 抽屉动效纯逻辑（0.7.1，chrome 裁决档 §3.5 S1–S8 的
/// 可测部分；档＝oneday-design-review/chrome-research-
/// 20261109.md，用户 2026-11-09 16:15 批准全案）：
/// 壳层只持一个 drawerOffset，本枚举管它的全部派生与
/// 判定——方向锁定（S2）、跟手位移换算（S2）、松手吸附
/// （S6）、圆角/阴影的白名单值（S3/§3.4）。弹簧本体在
/// OneDayDesign.MotionTokens.drawerSpring（S7）；挂载
/// 时机（S5）与呈现层接管（S7）在壳层 DrawerShell。
/// 0.17.0：抽屉改覆盖形态（调研报告 Q1/Q4 定案——被
/// 整体变换的页卡承载 TabView 是底栏下沉的病根），页
/// 卡退役，cornerRadius/shadowOpacity 自此无呈现层调
/// 用、保留作数据与回归钉；新增 scrimOpacity 承担覆
/// 盖形态的蒙层派生。位移三件（锁定/跟手/吸附）不变。
/// §313（第 78 条＋横扫 A-01/A-02）：几何定值单源迁
/// DrawerCardGeometry（本枚举同名白名单改转发）、新
/// 增 drawerOffset 锁步派生与深色阴影归零口径；位移
/// 三件与 scrim 化石保留不变。
/// §323（抽屉收口包，用户 2026-11-17 拍板「学好
/// 的」）：本枚举立为呈现派生的唯一通道——前景裁
/// 切几何（clipGeometry）自容器私收迁入、与既有
/// progress 派生同源；新增场景门谓词（学 Simplenote
/// shouldBegin 的 C/D/F 三道场合门，设计出处
/// drawer-in-mature-apps-survey-20261117.md §2.1，
/// GPL-2.0 只学设计不抄码）；松手吸附改 Proton 预
/// 测增量守卫两段式（出处同报告 §2.2，GPL-3.0 同
/// 口径）。
public enum DrawerMotion {
    /// S2 方向锁定：累计横向位移达到此值前手势不接管、
    /// 不写任何位移状态（纵滚零干扰）
    public static let directionLockDistance: CGFloat = 10
    /// S2 方向锁定：横纵比门槛（|dx| ≥ 1.5×|dy| 才算横拖）
    public static let directionLockRatio: CGFloat = 1.5
    /// S6 fling 直通：松手速度朝目标向超此值不看位置
    /// 直接吸附（pt/s）
    public static let flingVelocity: CGFloat = 800
    /// S6 预测位移吸附阈值：动量投影相对手势起点的偏
    /// 移过 travel 的三成即吸附到对岸（现行阈值沿用，
    /// 已合 momentum 语义——裁决档 §3.5 S6）。
    /// §323 起退出落定判定（改预测增量守卫两段式、
    /// 见 settleOpens），保留作沿革钉、不再有判定读点
    public static let settleFraction: CGFloat = 0.3
    /// 预测增量守卫带（§323，学 Proton Mail 落定判
    /// 定，SidebarScreen.swift 的 lastSwipeSignifi-
    /// canceThreshold 设计）：|predictedExtra| 超此
    /// 值才认松手甩动有效、信预测终点；否则按位置
    /// 过半定——治松手瞬间手指抽动把抽屉推向反向
    /// （出处 drawer-in-mature-apps-survey-20261117
    /// .md §2.2）。数值 25pt 为设计事实登记、实现自写
    public static let predictionGuard: CGFloat = 25
    /// S3 圆角一步到位阈值：progress 过此值圆角直接到
    /// 定值、拖动期不插值（逐帧改裁切半径＝整卡离屏
    /// 重合成，是 0.6.1 拖动卡顿主因之一，§1.5-2）。
    /// §313 起定值单源在 DrawerCardGeometry、本处只转发
    public static let cornerStepProgress: CGFloat =
        DrawerCardGeometry.cornerStepProgress
    /// 前景卡圆角定值（§202 对 Muse 新参照图重新拟
    /// 合定版：量测脚本 docs/drawer-edge-measurements/
    /// fit_corners.py——沿前景/底层亮度突变点采样做圆
    /// 拟合；参照图 5C33CA29…jpg 1206×2622、402 逻辑
    /// 宽 @3.0，顶弧 r＝158.5px、底弧 168.5px，四组独
    /// 立估计 156–174px，取池化中心 54.5pt；与纵向内
    /// 嵌走同心口径：r＋inset＝56.5pt，落在社区设备角
    /// 半径表 55–62pt 内。此前 43pt 是 §182.2 旧世代参
    /// 照（127d193a…jpg、393 逻辑宽、上角 132px）的拟
    /// 合值，随参照换代作废）。§313 起定值单源在
    /// DrawerCardGeometry、本处只转发
    public static let cardCornerRadius: CGFloat =
        DrawerCardGeometry.cornerRadius
    /// 纵向内嵌定值（§202 K1）：开态前景卡上/下各内嵌
    /// 此值、整卡浮置于抽屉面上，两弧连同顶/底短边完整
    /// 露出。参照图拟合顶 2.7pt/底 1.7pt（同上脚本），
    /// 对称取 2.0pt。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let cardVerticalInset: CGFloat =
        DrawerCardGeometry.verticalInset
    /// 柔影定值（§202 回宽）：§3.4 灰柱处方（radius 10
    /// /x −4、总宽约 20pt）的前提是平色近色面＋单条直
    /// 边、强阴影会摊成灰柱；K1/K2 后接缝主体是 54.5pt
    /// 大弧、要浮置必须有阴影绕角包裹，前提消失故回
    /// 宽——radius 18（定版区间 16–20，取中值偏上给大
    /// 弧留包裹宽度）。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let shadowRadius: CGFloat =
        DrawerCardGeometry.shadowRadius
    public static let shadowX: CGFloat =
        DrawerCardGeometry.shadowX
    /// 柔影峰值 alpha（progress=1 时）：§202 定 0.22
    /// （区间 0.18–0.25；开源同形态实现 eos 的 0.35×
    /// progress 是深底面参照，本 App 抽屉面浅色、取偏
    /// 低档）。拖动期 radius 与 x 冻结、只有 opacity 随
    /// progress 变（S3）。§313 起定值单源在 DrawerCard-
    /// Geometry、本处只转发
    public static let shadowMaxOpacity: Double =
        DrawerCardGeometry.shadowMaxOpacity
    /// 蒙层峰值 alpha（0.17.0 覆盖式抽屉）：页卡退役
    /// 后内容层静止不动，抽屉与内容的分离感改由滑入
    /// 抽屉下方的整屏蒙层承担（调研报告 Q4 结构 A）
    public static let scrimMaxOpacity: Double = 0.32

    /// S2 方向锁定判定：累计位移达标且横向主导才接管
    public static func isDirectionLocked(dx: CGFloat, dy: CGFloat) -> Bool {
        let ax = abs(dx)
        return ax >= directionLockDistance
            && ax >= directionLockRatio * abs(dy)
    }

    /// S1 派生语义：offset 过半记为开（供语义对账与命
    /// 中层开关；位移计算不读它——0.6.1 的 bool＋delta
    /// 双状态自此退役）
    public static func isOpen(offset: CGFloat, travel: CGFloat) -> Bool {
        travel > 0 && offset > travel / 2
    }

    /// S1 派生进度：钳制 0…1（橡皮筋越界段不放大进
    /// 度，缩放/阴影不被越界量带偏）
    public static func progress(offset: CGFloat, travel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(offset / travel, 0), 1)
    }

    /// 抽屉层锁步位移（第 78 条 D1/§313；越界钳制
    /// §318）：抽屉层与主面是同一个刚性平移——关闭
    /// 态抽屉整体左移恰好一个 travel 藏于主面之后，
    /// 开合全程抽屉位移＝主面位移 − travel（Muse
    /// 录屏五帧拟合 D(p)＝−travel·(1−p)，与 travel
    /// 全等，drawer-transform-prep-20261114.md
    /// §2.3）。**界内公式一字不变**；越界段（橡皮筋
    /// 段）§318 起钳制到 [−travel, 0]：§313 的「不钳
    /// 制、双层同量越界」在真机录屏实证露底——开向
    /// 过冲时抽屉层被带过 0、左缘离屏左约 52pt 露
    /// 出容器底色（诊断 drawer-broken-diagnosis-
    /// 20261117.md F2），Muse 基准全程无露底。钳
    /// 制后开向过冲抽屉钉死 0（面板左缘恒贴屏左、
    /// 前景独走橡皮筋）、关向过冲抽屉停在 −travel
    /// （整份藏好不深追）；前景橡皮筋手感与界内锁
    /// 步刚性均不受影响。travel 未量得（0）时恒 0
    public static func drawerOffset(
        offset: CGFloat, travel: CGFloat
    ) -> CGFloat {
        guard travel > 0 else { return 0 }
        return min(max(offset - travel, -travel), 0)
    }

    /// S2 跟手位移：接管后写入值扣除锁定段（消除旧实
    /// 现「含判定段全量写入」的起步跳，§1.5-5）；界内
    /// 1:1，越界段走 DrawerGeometry 橡皮筋（c＝0.55，
    /// §3.5 S2 维持不动）
    /// - startOffset: 接管瞬间的呈现位移
    /// - translation: 手势当前全量横向位移（自手势起点）
    /// - lockTranslation: 接管瞬间的手势横向位移（锁定段）
    public static func followedOffset(
        startOffset: CGFloat,
        translation: CGFloat,
        lockTranslation: CGFloat,
        travel: CGFloat
    ) -> CGFloat {
        let target = startOffset + (translation - lockTranslation)
        if target > travel {
            return travel + DrawerGeometry.rubberBand(
                overshoot: target - travel, containerWidth: travel
            )
        }
        if target < 0 {
            return -DrawerGeometry.rubberBand(
                overshoot: -target, containerWidth: travel
            )
        }
        return target
    }

    /// S6 松手吸附（§323 改两段式，学 Proton Mail 的
    /// 预测增量守卫——出处 drawer-in-mature-apps-
    /// survey-20261117.md §2.2，设计移植、实现自
    /// 写）：fling 直通优先；其下两段——
    /// ① 守卫段：|predictedExtra| 过 predictionGuard
    /// （25pt）才认甩动有效，按预测终点相对接管起
    /// 点的符号定开/合（预测终点落回起点开侧＝开）；
    /// ② 位置段：无有效甩动（慢拖松手）按当前位
    /// 置过半定（Proton isCloserToOpenThanClosed
    /// 同式）。§323 前的「相对偏移过 30% travel」
    /// 单阈口径（settleFraction）就此退役：慢拖到
    /// 三成即开的宽松口径与松手抽动误判同源，两段
    /// 式逐项由单测钉死
    /// - currentOffset: 松手瞬间位移
    /// - startOffset: 本次手势接管时的位移（守卫段的符号原点）
    /// - predictedExtra: predictedEndTranslation − translation（动量外推增量；壳层以速度×settleProjectionInterval 近似，§322）
    /// - velocityX: 松手速度（pt/s，右为正）
    public static func settleOpens(
        currentOffset: CGFloat,
        startOffset: CGFloat,
        predictedExtra: CGFloat,
        velocityX: CGFloat,
        travel: CGFloat
    ) -> Bool {
        guard travel > 0 else { return false }
        if velocityX > flingVelocity { return true }
        if velocityX < -flingVelocity { return false }
        if abs(predictedExtra) > predictionGuard {
            return (currentOffset - startOffset) + predictedExtra > 0
        }
        return currentOffset > travel / 2
    }

    // MARK: - §323 场景门（学 Simplenote shouldBegin 的 C/D/F）

    /// 开抽屉手势的场景事实快照（§323）：容器在
    /// gestureRecognizerShouldBegin 时点采集、喂
    /// allowsOpenGesture 判定——判定纯函数可测、采
    /// 集尽力而为（宿主层级扫描，未见结构按「无阻
    /// 碍」计，见容器注）。设计出处：Simplenote
    /// SPSidebarContainerViewController 的 shouldBegin
    /// 七门中 C（任一侧表格 dragging 中）/D（关态主
    /// 导航栈深度 >1）/F（侧栏编辑态）三道场合门
    /// （drawer-in-mature-apps-survey-20261117.md
    /// §2.1）；方向门 A/B 属方向判定、本仓已有更严
    /// 的三件套（10pt＋1.5 比＋失败依赖），不重复立
    public struct GestureScene: Equatable {
        /// 内容侧列表正在拖动（门 C 内容半）
        public var contentListDragging: Bool
        /// 抽屉侧列表正在拖动（门 C 抽屉半）
        public var drawerListDragging: Bool
        /// 内容侧导航栈深度（门 D；未见导航结构恒 1）
        public var contentNavigationDepth: Int
        /// 任一侧处于编辑态（门 F）
        public var isEditing: Bool

        public init(
            contentListDragging: Bool,
            drawerListDragging: Bool,
            contentNavigationDepth: Int,
            isEditing: Bool
        ) {
            self.contentListDragging = contentListDragging
            self.drawerListDragging = drawerListDragging
            self.contentNavigationDepth = contentNavigationDepth
            self.isEditing = isEditing
        }
    }

    /// 场景门判定：三道场合门任一命中即不开抽屉
    /// （C：任一侧列表 dragging 中；D：内容导航栈
    /// 深度 >1——深层页左缘是系统返回手势的领地；
    /// F：编辑态）。全不命中才放行；方向是否横向
    /// 主导仍由手势接管后的方向锁定判（本谓词不管
    /// 方向、只管场合）
    public static func allowsOpenGesture(scene: GestureScene) -> Bool {
        if scene.contentListDragging || scene.drawerListDragging {
            return false
        }
        if scene.contentNavigationDepth > 1 {
            return false
        }
        if scene.isEditing {
            return false
        }
        return true
    }

    // MARK: - §323 前景裁切几何（派生单源迁入）

    /// 前景裁切几何（§323 起派生单源在本枚举、与
    /// progress 同源）：clip 帧＝前景尺寸纵向内嵌
    /// verticalInset(progress)（合态 0、开态满值、
    /// 随 progress 线性行进）、半径＝cornerRadius
    /// (progress)（一步到位、K4 不插值）；内容宿主
    /// 反向补偿：原点 −inset、高恒前景高——宿主在
    /// 前景空间内的几何与 §202 之前逐值一致，浮置
    /// 只是裁切窗的事。此前本派生以私收形式住在容
    /// 器里、被 layout 与 applyOffset 两处调用写
    /// 帧（双调用点）；§323 迁入本枚举立唯一派生
    /// 通道，容器侧只许 applyOffset 一处按本派生
    /// 写帧（单写点，学 Simplenote 单 animator 单
    /// 写点——同报告 §2.1）
    /// §351 起容器不再按本派生逐帧写帧（刚体化：
    /// 三层帧钉全幅、内嵌改整卡 transform 等效，
    /// 见 cardScaleY/cardLeadingShift 与 DESIGN
    /// §351）；本派生退为几何口径档案——值不变、
    /// 单测保留（新旧等价关系由 cardScaleY 的派
    /// 生式保证）
    public static func clipGeometry(
        progress: CGFloat, foregroundSize: CGSize
    ) -> (clipFrame: CGRect, contentFrame: CGRect, radius: CGFloat) {
        let radius = cornerRadius(progress: progress)
        let inset = verticalInset(progress: progress)
        let bounds = CGRect(origin: .zero, size: foregroundSize)
        let clipFrame = bounds.insetBy(dx: 0, dy: inset)
        let contentFrame = CGRect(
            x: 0, y: -inset,
            width: bounds.width, height: bounds.height
        )
        return (clipFrame, contentFrame, radius)
    }

    /// S3 圆角：progress 过阈一步到定值（拖动期冻结）
    public static func cornerRadius(progress: CGFloat) -> CGFloat {
        progress > cornerStepProgress ? cardCornerRadius : 0
    }

    /// 内嵌随 progress 线性行进（§202 K1）：合态 0、开
    /// 态满值。帧写与 transform 同拍；与 K4「半径不逐
    /// 帧插值」不冲突——防卡顿定案管的是裁切路径重建，
    /// 内嵌只是帧位移、无路径重算
    /// §351 注：该「无路径重算」的定案被真机录屏证
    /// 伪一半——帧位移本身虽不重建路径，但 clip 层
    /// bounds 逐帧变使裁切子树逐帧重合成、宿主帧逐
    /// 帧写亦是呈现侧成本（DESIGN §351 定因）；呈现
    /// 已改整卡 transform 等效（cardScaleY），本派生
    /// 只余换算与档案职责
    public static func verticalInset(progress: CGFloat) -> CGFloat {
        cardVerticalInset * min(max(progress, 0), 1)
    }

    /// 卡面横向内缩（§351，深色接缝中间层）：深色
    /// 随 progress 线性行进至 DrawerCardGeometry.
    /// darkCardLeadingInset、浅色恒 0。卡面（裁切
    /// 层＋投影层）以 transform 右移此值、内容宿主
    /// 反向平移抵消（窗口位移对内容透明、与 §202
    /// 反向补偿同构）；露出带读前景底色 Palette.
    /// drawerBackdrop（深 #191919）
    public static func cardLeadingShift(
        progress: CGFloat, appearance: ShadowAppearance
    ) -> CGFloat {
        switch appearance {
        case .dark:
            return DrawerCardGeometry.darkCardLeadingInset
                * min(max(progress, 0), 1)
        case .light:
            return 0
        }
    }

    /// 卡面纵向刚体缩放（§351）：K1 纵向内嵌改整
    /// 卡 scaleY 等效——(H − 2·inset) / H，与旧帧
    /// 几何（clip 帧 insetBy(dy:)）逐值等价：卡面
    /// 上下沿位置与旧口径一致、帧本身钉死不写。
    /// 2026-11-22 Muse 视频量测其开合为纯平移、
    /// 无纵向缩放——本 App 的 2pt 内嵌本就近乎不
    /// 可见（H=852 时 scaleY≈0.9953），等效换算只
    /// 为保住 §202 既定浮置几何、不引入新视觉量
    public static func cardScaleY(
        progress: CGFloat, foregroundHeight: CGFloat
    ) -> CGFloat {
        guard foregroundHeight > 0 else { return 1 }
        let inset = verticalInset(progress: progress)
        return (foregroundHeight - 2 * inset) / foregroundHeight
    }

    /// S3/§3.4 阴影不透明度：白名单内唯一随 progress
    /// 变的阴影属性（浅色口径；深色见下方带外观参数
    /// 的重载）
    public static func shadowOpacity(progress: CGFloat) -> Double {
        shadowMaxOpacity * Double(min(max(progress, 0), 1))
    }

    /// 阴影外观（第 78 条 D4）：Muse 录屏深色帧段无
    /// 可量测阴影（缘口 1–2px 抗锯齿内完成亮度跳变、
    /// 无柔影带），深色口径归零；浅色保留 §202 定值
    /// （双口径各待一次真机对账）
    public enum ShadowAppearance {
        case light
        case dark
    }

    /// 带外观的阴影不透明度：深色恒 0、浅色走 S3 口径
    public static func shadowOpacity(
        progress: CGFloat, appearance: ShadowAppearance
    ) -> Double {
        switch appearance {
        case .dark:
            return 0
        case .light:
            return shadowOpacity(progress: progress)
        }
    }

    /// 蒙层不透明度（0.17.0）：随 progress 线性、两端
    /// 钳制——橡皮筋越界段不放大蒙层（与 progress 的
    /// 钳制口径一致，越界只动抽屉本体）
    public static func scrimOpacity(progress: CGFloat) -> Double {
        scrimMaxOpacity * Double(min(max(progress, 0), 1))
    }
}
