import EventKit
import EventKitUI
import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 本机连接器详情页组（0.34.0 批一，设计档 §6.2 通
/// 用骨架）：状态头（系统权限行＋调用去向行＋「允
/// 许智能体调用」开关＋设备会话态＋最近调用元数据）
/// → 内容区（逐件形态）→ 口径脚注。被拒/未授权时内
/// 容区换降级说明、不留空白页；每次进页重读系统权
/// 限（不缓存上次的绿）。
/// 0.36.3（详情页语法重做，用户 18:05 点名）：状
/// 态头按五段式模板重排——瓷砖＋名称＋一句话能力
/// 领头（居中）、系统权限行带可操作控件（S4）、
/// 开关副文压一行、门面口径下沉节脚注；三页撤
/// .navigationTitle 居中标题、内容领头。
///
/// 诚实边界（本版）：设备会话在线只说明手机侧通道
/// 活着；Hermes 侧工具门面注册留收官窗口——状态头
/// 与总览页都明说「智能体实际调用待服务器侧开通」，
/// 不许写成已可调用。

// MARK: - 设备五件图标（0.36.5，宪法 §4 修订）
// 0.36.0 的「白底＋SF 字形」瓷砖退役：宪法 §4 已
// 于 2026-11-10 19:19 经用户批准修订——指称具体
// 苹果系统应用时按官方构图自绘复刻（§4 第三源
// (a)、禁仿绘的唯一例外）。五件全部代码矢量自
// 绘，构图与色值以官方商店 artwork 设计期采样对
// 版（采样值见调研报告 apple-app-icons-research
// §5 与本轮像素实测）；商店原图只作对版、禁入
// 包。台账 D 节按「自绘复刻」如实登记。
// 健康一件与调研旧口径有出入：现行官方图为粉红
// 渐变心、心内无白色心电折线（像素实测无折线、
// 两条独立检索描述同此）——按现行官方图画渐变
// 心、不画折线；旧口径「红心＋白折线」是经典款
// 印象，若真机主屏幕为经典款再按实拍改。

struct DeviceAppIconView: View {
    let source: DeviceSourceID
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            baseColor
            artwork
        }
        .frame(width: size, height: size)
        .clipShape(iconShape)
        .overlay {
            iconShape.strokeBorder(Palette.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: size * 0.26, style: .continuous
        )
    }

    /// 底色：五件皆浅底（通讯录图内实测 ≈
    /// (245, 245, 245) 的极浅灰，余四件白）。图
    /// 标是固定 artwork、深浅模式同值（与真实应
    /// 用图标同理）
    private var baseColor: Color {
        switch source {
        case .contacts:
            return Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
        case .calendar, .reminders, .health, .home:
            return .white
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch source {
        case .calendar: calendarArtwork
        case .reminders: remindersArtwork
        case .contacts: contactsArtwork
        case .health: healthArtwork
        case .home: homeArtwork
        }
    }

    // 日历：白底＋红色星期（上部）＋黑色大日期，
    // 且是动态真实日期——TimelineView 每日刷新，
    // 星期/日期取渲染当日（与系统日历图标同理）
    private var calendarArtwork: some View {
        TimelineView(
            .periodic(
                from: Calendar.current.startOfDay(for: .now),
                by: 24 * 60 * 60
            )
        ) { context in
            VStack(spacing: 0) {
                Text(weekdayText(context.date))
                    .font(.system(size: size * 0.19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF3B30))
                    .padding(.top, size * 0.08)
                Text(dayText(context.date))
                    .font(.system(size: size * 0.5, weight: .light))
                    .foregroundStyle(.black)
            }
            .frame(width: size, height: size, alignment: .top)
        }
    }

    private func weekdayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    private func dayText(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        return String(day)
    }

    // 提醒事项：白底三行——圆点自上而下蓝（采样
    // ≈ #0195FF）/红 #FF3B30/橙 #FF9500＋浅灰
    // 横线（圆点取实心，官方图的玻璃环光泽省）
    private var remindersArtwork: some View {
        let rows: [(y: CGFloat, color: Color)] = [
            (0.28, Color(hex: 0x0195FF)),
            (0.50, Color(hex: 0xFF3B30)),
            (0.72, Color(hex: 0xFF9500)),
        ]
        return ZStack {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Circle()
                    .fill(row.color)
                    .frame(width: size * 0.16, height: size * 0.16)
                    .position(x: size * 0.24, y: size * row.y)
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(Color(hex: 0xD8D8DC))
                    .frame(width: size * 0.40, height: size * 0.075)
                    .position(x: size * 0.61, y: size * row.y)
            }
        }
        .frame(width: size, height: size)
    }

    // 通讯录：浅灰底＋灰人像剪影（头圆＋肩椭圆，
    // 剪影灰实测 ≈ (177, 173, 161)）＋右缘三只
    // 彩签（现行官方图实测彩签仍在——蓝/橙/绿，
    // 「iOS 26 去彩签」弱源不成立、不采）
    private var contactsArtwork: some View {
        let silhouette = Color(
            red: 177 / 255, green: 173 / 255, blue: 161 / 255
        )
        let tabs: [(y: CGFloat, color: Color)] = [
            (0.30, Color(red: 77 / 255, green: 190 / 255, blue: 246 / 255)),
            (0.50, Color(red: 255 / 255, green: 142 / 255, blue: 1 / 255)),
            (0.70, Color(red: 49 / 255, green: 217 / 255, blue: 82 / 255)),
        ]
        return ZStack {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                RoundedRectangle(cornerRadius: size * 0.02)
                    .fill(tab.color)
                    .frame(width: size * 0.10, height: size * 0.17)
                    .position(x: size * 0.96, y: size * tab.y)
            }
            Circle()
                .fill(silhouette)
                .frame(width: size * 0.30, height: size * 0.30)
                .position(x: size * 0.44, y: size * 0.38)
            Ellipse()
                .fill(silhouette)
                .frame(width: size * 0.54, height: size * 0.40)
                .position(x: size * 0.44, y: size * 0.80)
        }
        .frame(width: size, height: size)
    }

    // 健康：白底＋粉红渐变心（采样：中段 ≈
    // (255, 2, 74)、下段 ≈ (255, 0, 34)），
    // 无心电折线（见本节头注的出入登记）
    private var healthArtwork: some View {
        heartPath(
            in: CGRect(
                x: size * 0.19, y: size * 0.21,
                width: size * 0.62, height: size * 0.58
            )
        )
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 255 / 255, green: 59 / 255, blue: 109 / 255),
                    Color(red: 255 / 255, green: 2 / 255, blue: 74 / 255),
                    Color(red: 255 / 255, green: 0 / 255, blue: 34 / 255),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// 心形（100×100 设计盒，四段贝塞尔的圆润心）
    private func heartPath(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x / 100 * rect.width,
                y: rect.minY + y / 100 * rect.height
            )
        }
        var path = Path()
        path.move(to: pt(50, 88))
        path.addCurve(
            to: pt(8, 40),
            control1: pt(28, 70), control2: pt(8, 56)
        )
        path.addCurve(
            to: pt(30, 10),
            control1: pt(8, 26), control2: pt(16, 10)
        )
        path.addCurve(
            to: pt(50, 26),
            control1: pt(40, 10), control2: pt(47, 17)
        )
        path.addCurve(
            to: pt(70, 10),
            control1: pt(53, 17), control2: pt(60, 10)
        )
        path.addCurve(
            to: pt(92, 40),
            control1: pt(84, 10), control2: pt(92, 26)
        )
        path.addCurve(
            to: pt(50, 88),
            control1: pt(92, 56), control2: pt(72, 70)
        )
        path.closeSubpath()
        return path
    }

    // 家庭：白底＋橙黄实心房子（经典轮廓扁平复
    // 刻：宽檐屋顶＋门洞凹口；现行官方图的玻璃
    // 多层嵌套不复刻——扁平轮廓辨识度优先）
    private var homeArtwork: some View {
        housePath(
            in: CGRect(
                x: size * 0.08, y: size * 0.14,
                width: size * 0.84, height: size * 0.72
            )
        )
        .fill(
            LinearGradient(
                colors: [
                    Color(red: 255 / 255, green: 204 / 255, blue: 0 / 255),
                    Color(red: 255 / 255, green: 149 / 255, blue: 0 / 255),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    /// 房子轮廓（100×100 设计盒：屋顶宽檐出挑、
    /// 底部中央门洞以路径凹口成形）
    private func housePath(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x / 100 * rect.width,
                y: rect.minY + y / 100 * rect.height
            )
        }
        var path = Path()
        path.move(to: pt(50, 8))
        path.addLine(to: pt(97, 46))
        path.addLine(to: pt(88, 46))
        path.addLine(to: pt(88, 90))
        path.addLine(to: pt(64, 90))
        path.addLine(to: pt(64, 66))
        path.addLine(to: pt(36, 66))
        path.addLine(to: pt(36, 90))
        path.addLine(to: pt(12, 90))
        path.addLine(to: pt(12, 46))
        path.addLine(to: pt(3, 46))
        path.closeSubpath()
        return path
    }
}

// MARK: - 状态头（五件共用）

struct DeviceStatusHeader: View {
    @Environment(AppState.self) private var appState
    let source: DeviceSourceID

    private var controller: DeviceSessionController { appState.deviceSession }
    private var descriptor: DeviceSourceDescriptor {
        DeviceSourceDirectory.descriptor(source)
    }
    private var permission: DevicePermissionState {
        controller.permissions[source] ?? .notDetermined
    }

    /// 通道脚注（0.36.10）：只由本地可验事实拼——
    /// 系统权限、调用开关、设备会话在线三件，与目
    /// 录行状态字同源同口径，不许再出现 App 验不了
    /// 的服务端状态宣称
    private var channelNote: String {
        guard permission.isUsable else {
            return "先在上方开好系统权限，智能体才有机会调用这一件。"
        }
        guard controller.agentCallEnabled[source] ?? false else {
            return "调用开关已关：智能体问不到这一件，数据不会被调用。"
        }
        if controller.sessionOnline {
            return "设备会话在线：智能体发来调用时，这台手机现读现回，数据只过境、不存服务器。"
        }
        return "设备会话当前未连接：智能体现在叫不到这台手机；回到 App 前台、会话恢复在线后才可调用。"
    }

    var body: some View {
        Group {
            // 领头段（0.36.3，详情页语法五段式）：
            // 居中大真图标（苹果画法瓷砖 64）→名称→
            // 一句话能力说明。旧设置式分组头＋居中
            // 导航标题退役（对照授权页参考图）
            Section {
                VStack(spacing: OneDayMetrics.spacingS) {
                    DeviceAppIconView(source: source, size: 64)
                    Text(descriptor.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text(descriptor.blurb)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingSM)
            }
            .listRowBackground(Color.clear)

            Section {
                permissionRow
                Toggle(isOn: agentCallBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("允许智能体调用")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        // 0.36.3：副文压到一行短文案
                        // （capabilityLine），长说明
                        // agentNote 不再成段塞卡
                        Text(descriptor.capabilityLine)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                headerText("授权与调用")
            }
            .listRowBackground(Palette.surface)

            Section {
                detailRow(
                    "设备会话",
                    controller.sessionOnline ? "在线" : "离线"
                )
                if let entry = controller.lastCallEntries[source] {
                    detailRow("最近调用", entry.summaryLine)
                    detailRow(
                        "调用时刻",
                        DisplayDate.dateTime(
                            Date(timeIntervalSince1970: entry.at)
                        )
                    )
                    detailRow("调用工具", entry.tool)
                } else {
                    detailRow("最近调用", "暂无调用记录")
                }
                if let error = controller.sessionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            } header: {
                headerText("通道状态")
            } footer: {
                // 0.36.10（判词 3/4 口径统一）：旧静态
                // 句「待服务器侧门面注册开通」整句退
                // 役——那是 App 验不了的服务端状态、又
                // 与目录行「可调用」互斥打架；改由本地
                // 可验事实动态拼（channelNote），与目
                // 录行 DeviceRowStatus 同源同口径
                Text(channelNote)
            }
            .listRowBackground(Palette.surface)
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
        )
    }

    /// 系统权限行（0.36.5，用户 19:03 点名改开关
    /// 式控件；0.36.3 的「去开启/去设置」按钮与整
    /// 行点按式退役，S4「权限行须带动作」的口径由
    /// 开关承接）：样式是开关、行为不造假——平台
    /// 实情：应用内关不掉已授出的系统权限。落法：
    /// · 未定：拨开→触发系统权限请求（request-
    ///   Access 走真实授权流并回读状态，开关随真
    ///   实结果落位、不预先假开）；
    /// · 被拒/受限/仅写入：开关呈关态，拨开→跳系
    ///   统设置（系统不再弹请求框，只能去设置开）；
    /// · 已授权/有限：开关呈开态，拨关→跳系统设
    ///   置由用户在系统侧关，App 不假装已关。
    /// 状态文案（permission.label）留在标题右侧如
    /// 实报态。与下方「允许智能体调用」是两个独
    /// 立开关：系统权限（系统层）vs 应用内授权
    /// （续编 S3 双层语义），互不联动、各自落账。
    private var permissionRow: some View {
        Toggle(isOn: permissionBinding) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                permissionTitle
                Text(permission.label)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private var permissionBinding: Binding<Bool> {
        Binding(
            get: { permission.isUsable },
            set: { newValue in
                if newValue {
                    switch permission {
                    case .notDetermined:
                        Task {
                            await controller.requestAccess(for: source)
                        }
                    case .denied, .restricted, .writeOnly:
                        openSystemSettings()
                    case .granted, .limited:
                        break
                    }
                } else if permission.isUsable {
                    openSystemSettings()
                }
            }
        )
    }

    private var permissionTitle: some View {
        Text("系统权限")
            .font(.rowTitleL)
            .foregroundStyle(Palette.ink)
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private var agentCallBinding: Binding<Bool> {
        Binding(
            get: { controller.agentCallEnabled[source] ?? false },
            set: { controller.setAgentCallEnabled(source, $0) }
        )
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(title)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }
}

private func headerText(_ title: String) -> some View {
    Text(title)
        .font(.sectionLabel)
        .foregroundStyle(Palette.inkSecondary)
        .textCase(nil)
}

private let deviceRowInsets = EdgeInsets(
    top: 0, leading: 20, bottom: 0, trailing: 20
)

/// 未授权/被拒时的降级说明（内容区替换，不留空白页）
private struct DevicePermissionGate: View {
    let source: DeviceSourceID
    let permission: DevicePermissionState

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                Text(gateTitle)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(gateMessage)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                if source == .calendar, permission == .writeOnly {
                    Text("在系统设置里改成「完全访问」后，这里就能看到安排。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingS)
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(deviceRowInsets)
    }

    private var gateTitle: String {
        switch permission {
        case .notDetermined: return "还没有授权"
        case .denied, .restricted: return "系统权限被拒"
        case .writeOnly: return "当前只有写入权限"
        default: return "暂不可用"
        }
    }

    /// 降级说明（0.36.3 瘦身）：一句事实＋一个下
    /// 一步，不成段（续编 S11 空态句式同理）
    private var gateMessage: String {
        let name = DeviceSourceDirectory.descriptor(source).name
        switch permission {
        case .notDetermined:
            return "打开上方「系统权限」开关，系统会问你是否允许读取\(name)。"
        case .denied, .restricted:
            return "拨动上方「系统权限」开关会跳到系统设置，打开\(name)权限后即可。"
        case .writeOnly:
            return "当前只有写入权限，看不到已有安排。"
        default:
            return "当前状态下读不到数据。"
        }
    }
}

/// 口径脚注（详情页尾）
private struct DeviceFootnote: View {
    let source: DeviceSourceID

    var body: some View {
        Section {
            Text(DeviceSourceDirectory.descriptor(source).footnote)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(deviceRowInsets)
    }
}

/// sheet 内禁用下拉刷新（0.36.5）：详情以 sheet
/// 呈现时下拉手势归 sheet 的交互式关闭——
/// refreshable 在场会先行截走下拉，用户 19:08 点
/// 名的「下拉返回不了」实因在此；push 呈现（设
/// 置页）无此冲突、保留下拉刷新。三页详情共用
private struct RefreshableIfEnabled: ViewModifier {
    let enabled: Bool
    // 隔离标注：refreshable 的 action 形参要
    // @Sendable，全局 actor 隔离的函数值可直接转
    // 入；三页的 load 本就跑在 MainActor（视图上
    // 下文），标注只是把既成事实写明
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.refreshable(action: action)
        } else {
            content
        }
    }
}

// MARK: - 日历详情（议程形态，今起 14 天）

/// 议程按日分组（具名结构体承 ForEach 的 Identifiable）
private struct AgendaDayGroup: Identifiable {
    let day: Date
    let events: [DeviceAgendaEvent]
    var id: Date { day }
}

struct CalendarDetailView: View {
    @Environment(AppState.self) private var appState
    /// sheet 呈现标记（0.36.5）：为真时禁下拉刷新、
    /// 下拉归 sheet 关闭；默认 false（push 路径）
    var inSheet: Bool = false
    @State private var days: [AgendaDayGroup] = []
    @State private var showNewEvent = false

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.calendar] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .calendar)
            if permission.isUsable {
                agendaSections
            } else {
                DevicePermissionGate(source: .calendar, permission: permission)
            }
            DeviceFootnote(source: .calendar)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .toolbar {
            if permission.isUsable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建日程")
                }
            }
        }
        .sheet(isPresented: $showNewEvent) {
            EventEditView(
                store: controller.dispatcher.events.store
            ) {
                showNewEvent = false
                load()
            }
        }
        .task { load() }
        .modifier(
            RefreshableIfEnabled(enabled: !inSheet) { load() }
        )
    }

    @ViewBuilder
    private var agendaSections: some View {
        if days.isEmpty {
            Section {
                Text("接下来 14 天没有安排。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        ForEach(days) { group in
            Section {
                if group.events.isEmpty {
                    Text("这一天没有安排")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(group.events) { event in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Circle()
                            .fill(Color(hex: event.calendarColorHex))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text(eventSubline(event))
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                headerText(dayTitle(group.day))
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func eventSubline(_ event: DeviceAgendaEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var text = event.isAllDay
            ? "全天"
            : "\(formatter.string(from: event.start)) – \(formatter.string(from: event.end))"
        text += " · \(event.calendarName)"
        if let location = event.location, !location.isEmpty {
            text += " · \(location)"
        }
        return text
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        if calendar.isDateInToday(day) {
            return "今天 · \(formatter.string(from: day))"
        }
        if calendar.isDateInTomorrow(day) {
            return "明天 · \(formatter.string(from: day))"
        }
        return formatter.string(from: day)
    }

    private func load() {
        guard permission.isUsable else {
            days = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 14, to: start) ?? start
        let events = controller.dispatcher.events.events(from: start, to: end)
        var grouped: [Date: [DeviceAgendaEvent]] = [:]
        for event in events {
            grouped[calendar.startOfDay(for: event.start), default: []]
                .append(event)
        }
        var ordered: [AgendaDayGroup] = grouped
            .map { AgendaDayGroup(day: $0.key, events: $0.value) }
            .sorted { $0.day < $1.day }
        // 「今天」组恒在（没安排也显一行空态，设计档口径）
        if grouped[start] == nil {
            ordered.insert(AgendaDayGroup(day: start, events: []), at: 0)
        }
        days = ordered
    }
}

/// 系统新建日程编辑器（EKEventEditViewController 桥）
private struct EventEditView: UIViewControllerRepresentable {
    let store: EKEventStore
    var onFinish: () -> Void

    func makeUIViewController(
        context: Context
    ) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: EKEventEditViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            onFinish()
        }
    }
}

// MARK: - 提醒详情（按清单分组，未完成在前）

struct RemindersDetailView: View {
    @Environment(AppState.self) private var appState
    /// sheet 呈现标记（0.36.5）：同 CalendarDetailView
    var inSheet: Bool = false
    @State private var items: [DeviceReminderItem] = []
    @State private var showAdd = false
    @State private var actionError: String?

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.reminders] ?? .notDetermined
    }

    private var incomplete: [DeviceReminderItem] {
        items.filter { !$0.isCompleted }
    }

    private var listNames: [String] {
        var seen: [String] = []
        for item in incomplete where !seen.contains(item.listName) {
            seen.append(item.listName)
        }
        return seen
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .reminders)
            if permission.isUsable {
                reminderSections
            } else {
                DevicePermissionGate(
                    source: .reminders, permission: permission
                )
            }
            if let actionError {
                Section {
                    Text(actionError)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(deviceRowInsets)
            }
            DeviceFootnote(source: .reminders)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .toolbar {
            if permission.isUsable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建提醒")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddReminderView {
                showAdd = false
                Task { await load() }
            }
        }
        .task { await load() }
        .modifier(
            RefreshableIfEnabled(enabled: !inSheet) { await load() }
        )
    }

    @ViewBuilder
    private var reminderSections: some View {
        if incomplete.isEmpty {
            Section {
                Text("没有未完成的提醒。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        ForEach(listNames, id: \.self) { listName in
            let group = incomplete.filter { $0.listName == listName }
            Section {
                ForEach(group) { item in
                    reminderRow(item)
                }
            } header: {
                headerText("\(listName) · \(group.count) 项未完成")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func reminderRow(_ item: DeviceReminderItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Button {
                Task { await toggle(item) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("勾完成：\(item.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let subline = reminderSubline(item) {
                    Text(subline)
                        .font(.footnote)
                        .foregroundStyle(
                            item.isOverdue ? Palette.danger
                                : Palette.inkSecondary
                        )
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func reminderSubline(_ item: DeviceReminderItem) -> String? {
        guard let due = item.due else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        if item.isOverdue {
            let days = Calendar.current.dateComponents(
                [.day], from: due, to: Date()
            ).day ?? 0
            return days > 0
                ? "已过期 \(days) 天 · \(formatter.string(from: due))"
                : "已过期 · \(formatter.string(from: due))"
        }
        return formatter.string(from: due)
    }

    private func toggle(_ item: DeviceReminderItem) async {
        do {
            _ = try controller.dispatcher.events.setReminderCompleted(
                id: item.id, completed: true
            )
            actionError = nil
        } catch let error as DeviceToolError {
            actionError = error.message
        } catch {
            actionError = "勾完成失败"
        }
        await load()
    }

    private func load() async {
        guard permission.isUsable else {
            items = []
            return
        }
        items = await controller.dispatcher.events.reminderItems()
    }
}

/// 新建提醒小表（本地动作：标题＋可选到期）
private struct AddReminderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(3600)
    @State private var errorLine: String?
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("提醒标题", text: $title)
                Toggle("设到期时间", isOn: $hasDue)
                if hasDue {
                    DatePicker(
                        "到期", selection: $due,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
                if let errorLine {
                    Text(errorLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            title.trimmingCharacters(
                                in: .whitespaces
                            ).isEmpty
                        )
                }
            }
        }
    }

    private func save() {
        do {
            try appState.deviceSession.dispatcher.events
                .createReminderSimple(
                    title: title.trimmingCharacters(in: .whitespaces),
                    due: hasDue ? due : nil
                )
            onDone()
            dismiss()
        } catch let error as DeviceToolError {
            errorLine = error.message
        } catch {
            errorLine = "新建失败"
        }
    }
}

// MARK: - 通讯录详情（搜索现查，纯本地渲染）

struct ContactsDetailView: View {
    @Environment(AppState.self) private var appState
    /// sheet 呈现标记（0.36.5）：同 CalendarDetailView
    var inSheet: Bool = false
    @State private var items: [DeviceContactItem] = []
    @State private var query = ""
    @State private var loadError: String?
    @State private var selected: DeviceContactItem?

    private var controller: DeviceSessionController { appState.deviceSession }
    private var permission: DevicePermissionState {
        controller.permissions[.contacts] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .contacts)
            if permission.isUsable {
                contactsSections
            } else {
                DevicePermissionGate(
                    source: .contacts, permission: permission
                )
            }
            DeviceFootnote(source: .contacts)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.3：撤居中标题，领头段（瓷砖＋名称）即页头
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "搜索联系人"
        )
        .onChange(of: query) { _, _ in load() }
        .sheet(item: $selected) { contact in
            NavigationStack { contactDetail(contact) }
        }
        .task { load() }
        .modifier(
            RefreshableIfEnabled(enabled: !inSheet) { load() }
        )
    }

    @ViewBuilder
    private var contactsSections: some View {
        if permission == .limited {
            Section {
                Text("仅显示你勾选给 OneDay 的联系人（当前 \(items.count) 位）——受限授权下系统只给这部分，这是真实子集、不是全量。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        if let loadError {
            Section {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        } else if items.isEmpty {
            Section {
                Text(query.isEmpty ? "没有联系人。" : "没有匹配「\(query)」的联系人。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        } else {
            Section {
                ForEach(items) { contact in
                    Button {
                        selected = contact
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                if let phone = contact.phones.first {
                                    Text(phone)
                                        .font(.footnote)
                                        .foregroundStyle(
                                            Palette.inkSecondary
                                        )
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.inkSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(
                            minHeight: OneDayMetrics.settingsRowHeight
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            } header: {
                headerText("联系人 · \(items.count)")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
    }

    private func contactDetail(_ contact: DeviceContactItem) -> some View {
        List {
            Section {
                ForEach(contact.phones, id: \.self) { phone in
                    labeledRow("电话", phone)
                }
                ForEach(contact.emails, id: \.self) { email in
                    labeledRow("邮箱", email)
                }
                if let organization = contact.organization {
                    labeledRow("公司", organization)
                }
                if contact.phones.isEmpty && contact.emails.isEmpty {
                    Text("这位联系人没有电话或邮箱。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        // 0.36.0（§5／审计 C9）：撤手写关闭（走系统
        // 下拉手势）；标题是联系人名＝内容身份本身、
        // 非通用栏题，保留（台账 E2 豁免候选）
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .textSelection(.enabled)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func load() {
        guard permission.isUsable else {
            items = []
            return
        }
        do {
            let engine = controller.dispatcher.contacts
            items = query.trimmingCharacters(in: .whitespaces).isEmpty
                ? try engine.allContacts()
                : try engine.searchLocal(query: query)
            loadError = nil
        } catch let error as DeviceToolError {
            loadError = error.message
            items = []
        } catch {
            loadError = "通讯录读取失败"
            items = []
        }
    }
}

// MARK: - 设备与权限总览（设置页入口，设计档 §6.3）

/// 五件总览：授权状态＋调用开关汇总一张表，被拒在
/// 这里一眼可见；批二两件只显待权益、不给假入口
struct DevicePermissionsView: View {
    @Environment(AppState.self) private var appState

    private var controller: DeviceSessionController { appState.deviceSession }

    var body: some View {
        List {
            Section {
                ForEach(DeviceSourceDirectory.roster) { descriptor in
                    if descriptor.isWired {
                        NavigationLink {
                            detailDestination(descriptor.sourceID)
                        } label: {
                            overviewRow(descriptor)
                        }
                    } else {
                        overviewRow(descriptor)
                    }
                }
            } header: {
                headerText("你的设备")
            } footer: {
                Text("系统权限（iOS 管）与「允许智能体调用」（App 内开关）是两层：前者决定 App 能不能读，后者决定智能体能不能经调用拿到。健康与家庭还差系统签名权益，开通前只列名、不显数据。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)

            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("设备会话")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(controller.sessionOnline ? "在线" : "离线")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                // 0.36.10：旧句「还差服务器侧门面注册」
                // 是 App 验不了的服务端状态、且已与事
                // 实脱节，换本地可验口径
                Text("会话只在 App 前台时活着；未连接时智能体叫不到这台手机，回到前台会自动恢复连接。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            } header: {
                headerText("通道状态")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("设备与权限")
        .navigationBarTitleDisplayMode(.inline)
        .task { controller.refreshPermissions() }
    }

    private func overviewRow(
        _ descriptor: DeviceSourceDescriptor
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            DeviceAppIconView(source: descriptor.sourceID, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.name)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(overviewStatus(descriptor))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
    }

    private func overviewStatus(
        _ descriptor: DeviceSourceDescriptor
    ) -> String {
        let permission = controller.permissions[descriptor.sourceID]
            ?? .notDetermined
        return DeviceRowStatus.line(
            descriptor: descriptor,
            permission: permission,
            agentCallEnabled:
                controller.agentCallEnabled[descriptor.sourceID] ?? false,
            sessionOnline: controller.sessionOnline,
            metric: nil
        )
    }

    @ViewBuilder
    private func detailDestination(
        _ source: DeviceSourceID
    ) -> some View {
        switch source {
        case .calendar: CalendarDetailView()
        case .reminders: RemindersDetailView()
        case .contacts: ContactsDetailView()
        case .health, .home: EmptyView()
        }
    }
}

/// Color 十六进制便捷构造（瓷砖/日历色点共用）
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
