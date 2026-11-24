import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// A-11 结构拆分（2026-11-16）：自 GoalsView.swift 按职责拆出（列表行与共享行件），零行为变更（DESIGN §311）；goalActivityDotColor 因详情页跨文件共用去掉 private（可见性修饰），余逐字未改。

/// 未归类任务行（GD-2）：标题＋状态/来源小字＋右端
/// 「归组」菜单（选进行中目标即归组，动作经 onAssign
/// 回到列表页的 Store 调用）。独立成 View 与列表页
/// 解耦（同 GoalRowView 的拆分先例）
struct UngroupedTaskRowView: View {
    let row: BridgeUngroupedTask
    let detail: String
    let targets: [BridgeGoal]
    let onAssign: (String) -> Void

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: "checklist")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body)
                    .foregroundStyle(Palette.bodyInk)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                ForEach(targets, id: \.id) { goal in
                    Button(goal.title) {
                        onAssign(goal.id)
                    }
                }
            } label: {
                Text("归组")
                    .font(.body)
                    .foregroundStyle(Palette.primary)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingSM)
    }
}

/// 未归类任务管理页（§453，用户 2026-11-24 亲点）：
/// 原整区（说明段＋逐条归组行）占目标页主体，与 Muse
/// 目标页「纯目标列表」形态不符——整区移出主体、收进
/// 本页，目标页只留一行入口。功能一件不少：说明、行
/// 小字（状态＋来源）、归组菜单、失败注记全随区搬入。
/// 数据与动作仍走 GoalsStore 同一口（归组→回读刷新）。
/// 归类口径不变：只呈现＋用户点归，系统不自动归组
/// 【2026-11-14 19:05 用户拍板】；纯系统/定时任务不
/// 在此面（归台账）
struct UngroupedTasksView: View {
    @Environment(AppState.self) private var appState
    private var store: GoalsStore {
        appState.sharedGoalsStore()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("在对话里安排的、采纳点子时生成的任务，还没归到目标下。归组后，它的进展会记到那个目标里。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(store.ungroupedTasks, id: \.taskId) { row in
                        if row.taskId
                            != store.ungroupedTasks.first?.taskId {
                            GroupDivider()
                        }
                        UngroupedTaskRowView(
                            row: row,
                            detail: Self.rowDetail(row),
                            targets: store.goals.filter {
                                $0.status == .active
                            }
                        ) { goalID in
                            Task {
                                await store.assignUngroupedTask(
                                    appState: appState,
                                    taskID: row.taskId,
                                    toGoalID: goalID
                                )
                            }
                        }
                    }
                }
                if store.ungroupedTasks.isEmpty {
                    Text("暂时没有未归类的任务。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                }
                if let note = store.ungroupedNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .padding(.top, OneDayMetrics.spacingS)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, OneDayMetrics.spacingM)
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("未归类任务")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 未归类行小字：状态（桥给的原生状态经既有状态
    /// 呈现解析）＋来源；状态缺失时只给来源，不编
    /// （自 GoalsView 原 helper 随区搬入，口径逐字不变）
    private static func rowDetail(
        _ row: BridgeUngroupedTask
    ) -> String {
        let origin = UngroupedTaskPresentation.originLabel(row.origin)
        guard let status = row.status else { return origin }
        let label = KanbanStatusPresentation.resolve(
            status: status, blockKind: nil, lastFailureError: nil
        ).label
        return "\(label) · \(origin)"
    }
}

/// 分类七行（0.40.0）：图标＋类名＋右端「＋」，空态整页
/// 与分类选择 sheet 共用同一组件（规格第三章：同一分类
/// 组件两处复用）。图标走 SF Symbols 同语义位（宪法
/// §4），不仿绘参照图的 3D/字形原图
struct GoalCategoryRowsView: View {
    var onPick: (GoalCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(
                Array(GoalCategory.creationOrder.enumerated()),
                id: \.element
            ) { index, category in
                if index > 0 {
                    GroupDivider()
                }
                Button {
                    onPick(category)
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Image(systemName: category.symbolName)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(width: 24)
                        Text(category.title)
                            .font(.body)
                            .foregroundStyle(Palette.bodyInk)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                }
                .buttonStyle(.odPressable)
            }
        }
        .odGroup()
    }
}

/// 分类选择 sheet（有目标时从底部创建区/工具栏进入）：
/// 选完把分类交给上层换成介绍卡（同一个 sheet 内换
/// 内容，不叠第二层 sheet；§238 前是换新建表单）
struct GoalCategorySheetView: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (GoalCategory) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(
                    alignment: .leading, spacing: OneDayMetrics.spacingL
                ) {
                    Text("选一个类别，接下来在对话里把目标聊定。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                    GoalCategoryRowsView(onPick: onPick)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("创建目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .fullscreenPopBridge()
    }
}

/// 分类介绍卡（GA-1，§238；§459 形态改判，用户
/// 2026-11-24 05:54 亲点「还有目标一样」对齐
/// Muse）：点分类后的第二步——形态自全屏页改半
/// 屏 bottom sheet（固定高 detent、背景列表可见、
/// 系统圆角），内容照 Muse 原口径：题＋两段短文
/// 案（黑字）＋开始吧；分类图标与 introLead 撤出
/// 本卡（introLead 仍供开旁聊引用道 SourceQuote
/// 消费），长段灰字整段删除——其中「拆成哪些里
/// 程碑」是谎话（里程碑已随 G-6 全摘），永不许再
/// 出现。主钮「开始吧」＝开目标旁聊在对话里聊定
/// （GA-2 终局：目标由智能体在对话里经 goals_
/// create 落桥、source=chat）。
/// 开始吧配色归属：改饱和蓝底白字已由 108 主钮包
/// （feat/primary-button-unify @9390491，跟改清单
/// 明列本卡）覆盖——本包只改形态与文案，钮的取
/// 色两行归 108 包——0.50.111 合并时已按 108
/// 口径落 primarySaturated＋白字（见钮内注）。
/// 「直接填写」去向待主线裁（§459 交卷单列）：参
/// 照里没有这条路、按对齐口径倾向摘除，但属行为
/// 变更——本包原样保留、只报不裁（GA-1 旧定版
/// 「表单不删、只降次级」在裁决前继续有效）
struct GoalIntroView: View {
    let category: GoalCategory
    var onStart: () -> Void
    var onForm: () -> Void

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading, spacing: OneDayMetrics.spacingL
            ) {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingM
                ) {
                    Text("创建\(category.title)目标")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                    // 两段短文案照 Muse 参照原文（用
                    // 户 05:51 参照图逐字）：先在聊天
                    // 里一起完善、设定后在这里追踪
                    Text("首先，我们将在聊天中一起完善目标。我会问几个问题，准确了解你的目标。")
                        .font(.body)
                        .foregroundStyle(Palette.bodyInk)
                    Text("目标设置后，我会在这里追踪你的进度。")
                        .font(.body)
                        .foregroundStyle(Palette.bodyInk)
                }
                VStack(spacing: OneDayMetrics.spacingS) {
                    Button {
                        onStart()
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingS) {
                            // 对话气泡图标照 Muse 参照
                            // （§459 形态）；取色行归 108
                            // 包、本包不动（见类型注）
                            Image(systemName: "bubble.left")
                            Text("开始吧")
                        }
                        .font(.headline)
                        // 主按钮统一口径（2026-11-24 主线
                        // 裁决，§453 改判后续）：目标介绍
                        // 卡主钮同点子「开始吧」——饱和
                        // 蓝底＋白字（primarySaturated），
                        // 不再走第 85 条 BC-1 的
                        // primaryPale＋onPrimary 配对
                        // （§459 合并注：形态与文案取
                        // §459 半屏稿、取色以 108 主钮
                        // 包为准，本行即其落点）
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            Palette.primarySaturated, in: Capsule()
                        )
                    }
                    .buttonStyle(.odPressable)
                    Button {
                        onForm()
                    } label: {
                        Text("直接填写")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingL)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        // §459 半屏形态：固定高 detent（内容实高约
        // 330pt；参照 Muse 卡高占比 26% 是无「直接
        // 填写」行的形态，本卡含待裁行实高占比约
        // 36%——裁删后可再降，交卷对位表注明）；小
        // 屏/AX 大字号时内部 ScrollView 兜底可滚
        .presentationDetents([.height(344)])
        .presentationDragIndicator(.visible)
    }
}

/// 分组头（§485 全抄口径，照 Muse 目标页段头量
/// 测）：纯色点 Ø10（进行中＝success 绿、已完成＝
/// inkMuted 灰）＋组名 groupHeader 角色（Title3
/// 20 semibold、bodyInk 深色字）。旧形态（17pt
/// 浅绿底盘＋6.5pt 点＋.body semibold 绿字）整件
/// 退役——参照段头无底盘、字为深色（审计 D3）。
/// 已完成组头字阶/字色随进行中组统一（其折叠＋
/// 计数形态不变，审计 §四.3）
struct GoalGroupHeader: View {
    let title: String
    let completed: Bool

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Circle()
                .fill(completed ? Palette.inkMuted : Palette.success)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.groupHeader)
                .foregroundStyle(Palette.bodyInk)
        }
    }
}

/// 目标方形勾选框（22pt，照 Muse 行实测）：即状态开关
/// ——点框标完成/重开，走 PATCH 回读口径（调用方负责）
struct GoalCheckBox: View {
    let done: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                    .fill(done ? Palette.ink : Color.clear)
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusCheckbox, style: .continuous)
                    .strokeBorder(
                        done ? Color.clear
                            : Color(UIColor.opaqueSeparator),
                        lineWidth: 1.5
                    )
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            // §485：视觉框/命中域/布局三层分开——内
            // 层 frame 22 钉死绘制（旧实现形状无自
            // 身 frame、直接撑满 44 命中框绘制，
            // .padding(-11) 只缩布局不缩绘制、实
            // 渲 44＝参照 2 倍，审计 D5）；外层
            // frame 44＋contentShape 只承载命中；
            // .padding(-11) 只抵消命中层布局占
            // 用、绘制不经它缩放（0.36.0 的 44 命
            // 中口径 A11Y-V1/T1 不变）。描边改系
            // 统 separator 档浓度＝UIColor
            // .opaqueSeparator（实色 #C6C6C8，审
            // 计 D4 定版 ≈#C7C7CC 档；0.36.1
            // odGroup 描边同因改挂此色收口先例）：
            // 半透明 separator 在 iOS 26 解析
            // α＝0.12、压白实渲 #E8E8E8 与旧
            // hairline（#EEEEF0、白底对比
            // ≈1.1:1 等于没画，审计 D4）几乎无
            // 别——量测实证见 GoalsCopy478
            // MeasureTests
            .frame(width: 22, height: 22)
            .frame(
                width: OneDayMetrics.minTapTarget,
                height: OneDayMetrics.minTapTarget
            )
            .contentShape(Rectangle())
            .padding(-11)
        }
        .buttonStyle(.odPressable)
        // 开关语义（A11Y-V5）：动作标签＋状态值，
        // VoiceOver 能读出「这是什么开关、现在什么
        // 状态」，不再是无标签裸按钮
        .accessibilityLabel(done ? "重新打开目标" : "标记目标完成")
        .accessibilityValue(done ? "已完成" : "未完成")
        // 触感矩阵（0.36.2，规格 §2.3/§2.5）：勾选
        // 完成＝notification success；只在 未完成→
        // 完成 边沿响（done 是回读确认后的真状态，
        // 响在落定刻）；取消勾选不对称、不加
        .sensoryFeedback(.success, trigger: done) { old, new in
            !old && new
        }
    }
}

/// 目标扁平行：勾选框（状态开关）＋标题/进展摘要（点进
/// 详情）＋⋮ 菜单（编辑/状态/删除收进菜单，照设计档）
/// 活动状态点色（GD-1 呈现）：正在办＝主色、卡住
/// 了＝危险色、等着/闲置＝弱灰（与组头状态点同语
/// 义：色只表状态、不作装饰）
func goalActivityDotColor(
    _ state: GoalActivityState
) -> Color {
    switch state {
    case .running: return Palette.primary
    case .blocked: return Palette.danger
    case .waiting, .idle: return Palette.inkMuted
    }
}

struct GoalRowView: View {
    let store: GoalsStore
    let goal: BridgeGoal
    let summary: String
    let acting: Bool
    var onToggleStatus: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        // §485：横向间距 spacingSM 12→spacingS 8
        // （参照量测：框右缘→标题左缘 ≈8pt，审计
        // R5/R6）；复选框删 spacingMicro 顶补丁——
        // 视觉框回 22 后布局顶与标题首行同顶（顶
        // 差 ≤3pt，审计 §四.4），补丁式对齐退役
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            GoalCheckBox(done: goal.status == .completed) {
                onToggleStatus()
            }
            .disabled(acting)
            NavigationLink {
                GoalDetailView(store: store, goalID: goal.id)
            } label: {
                VStack(alignment: .leading, spacing: OneDayMetrics.stackGap) {
                    Text(goal.title)
                        // §364（台账 23，用户 2026-11-22
                        // 裁定）：行题同点子/动态例，改用
                        // contentListTitle（Title3 档
                        // semibold），破 C14 单轨——对位
                        // Muse 实测约 21pt semibold
                        .font(.contentListTitle)
                        .foregroundStyle(Palette.bodyInk)
                        // §485：lineLimit 2→1（照 Muse
                        // 目标页参照：标题单行呈现、长题
                        // 尾截断，审计 D7/R6）
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    if !summary.isEmpty {
                        Text(summary)
                            // §485：字阶 .body 17→rowSub-
                            // title 15（参照 ≈15–16pt 档，
                            // 审计 D8/R7）；lineSpacing
                            // -1 把行 pitch 自 20 压到
                            // 19±1（参照实测 19.0/18.7）
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineSpacing(-1)
                            // §364：截断 2→3 行（对位 Muse 2–3 行）
                            // §453 改判 4 行：用户 2026-11-24
                            // 截图实证 Muse 现状摘要全显可达
                            // 4 行，3 行会腰斩最新进展条目
                            // §485 再改判 3 行：全抄审计逐
                            // 帧量测参照摘要 ≤3 行、块高
                            // ≤57pt（D8/R7），§453 的 4
                            // 行口径就此被覆盖
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    // 活动行（GD-1 呈现，§238）：桥派生
                    // 的关联任务活动——状态点＋label 一
                    // 行（照 Linear 名单行 health 信号
                    // 的摆法：小状态信号＋最近进展）。
                    // 只对进行中目标且真有关联任务时
                    // 显；无关联/旧桥无 activity 时整行
                    // 不出，不拿别的数据脑补
                    if goal.status == .active,
                       let activity = goal.activity,
                       activity.linkedCount > 0 {
                        HStack(
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Circle()
                                .fill(
                                    goalActivityDotColor(
                                        activity.state
                                    )
                                )
                                .frame(width: 7, height: 7)
                            Text(activity.label)
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.odPressable)
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("编辑目标", systemImage: "pencil")
                }
                Button {
                    onToggleStatus()
                } label: {
                    Label(
                        goal.status == .completed ? "重新打开" : "标为完成",
                        systemImage: goal.status == .completed
                            ? "arrow.uturn.backward" : "checkmark.circle"
                    )
                }
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除目标", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .rotationEffect(.degrees(90))
                    .frame(
                        width: OneDayMetrics.minTapTarget,
                        height: OneDayMetrics.minTapTarget
                    )
                    .contentShape(Rectangle())
            }
            // 0.43.0（A11Y-V6）：⋮ 菜单钮补标签（文件
            // 行同钮已有「更多操作」先例，此处对齐）
            .accessibilityLabel("更多操作")
            .disabled(acting)
        }
    }

}
