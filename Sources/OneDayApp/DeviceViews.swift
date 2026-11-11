import EventKit
import EventKitUI
import OneDayCore
import OneDayDesign
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 本机连接器详情页组（0.34.0 批一，设计档 §6.2 通
/// 用骨架）：状态头 → 内容区（逐件形态）。被拒/
/// 未授权时内容区换降级说明、不留空白页；每次进
/// 页重读系统权限（不缓存上次的绿）。0.36.18 起
/// 记录型五件的状态头只剩领头段（大图标＋名称＋
/// 一句副题）——权限开关/状态字/日志在同步区
/// （DeviceSyncViews），授权区、通道状态区与页尾
/// 口径脚注整组退役；健康/家庭保持原双层状态头
/// （权限开关＋允许调用＋通道状态）不动。
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
        case .alarm:
            // 时钟应用官方图即黑底
            return .black
        case .calendar, .reminders, .photos, .motion, .health, .home,
             .clipboard, .files, .notifications, .opener,
             .camera, .vision, .translate, .ondevice, .biometric,
             .location, .media, .compose, .shortcuts, .deviceinfo:
            return .white
        }
    }

    @ViewBuilder
    private var artwork: some View {
        switch source {
        case .calendar: calendarArtwork
        case .reminders: remindersArtwork
        case .contacts: contactsArtwork
        case .photos: photosArtwork
        case .motion: motionArtwork
        case .health: healthArtwork
        case .home: homeArtwork
        case .clipboard: clipboardArtwork
        case .files: filesArtwork
        case .alarm: alarmArtwork
        case .notifications: notificationsArtwork
        case .opener: openerArtwork
        case .camera: cameraArtwork
        case .vision: visionArtwork
        case .translate: translateArtwork
        case .ondevice: ondeviceArtwork
        case .biometric: biometricArtwork
        case .location: locationArtwork
        case .media: mediaArtwork
        case .compose: composeArtwork
        case .shortcuts: shortcutsArtwork
        case .deviceinfo: deviceinfoArtwork
        }
    }

    // 时钟（闹钟的系统归属「时钟」应用）：按官方构
    // 图复刻——黑底＋白表盘＋黑时分针＋橙秒针。系
    // 统图标走的是实时走字，本复刻是静止表盘（钉在
    // 十点零九分），不装实时
    private var alarmArtwork: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size * 0.80, height: size * 0.80)
            handLayer(
                length: 0.23, width: 0.055, color: .black,
                angle: -60
            )
            handLayer(
                length: 0.32, width: 0.055, color: .black,
                angle: 54
            )
            handLayer(
                length: 0.35, width: 0.02,
                color: Color(hex: 0xFF9500), angle: 160
            )
            Circle()
                .fill(.black)
                .frame(width: size * 0.07, height: size * 0.07)
        }
        .frame(width: size, height: size)
    }

    /// 表针层：整层旋转，针绕表盘中心转（针身自中
    /// 心向上伸出 length 比例）
    private func handLayer(
        length: CGFloat, width: CGFloat, color: Color,
        angle: Double
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(color)
                .frame(
                    width: size * width, height: size * length
                )
                .offset(y: -size * length / 2)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
    }

    // 通知（设备扩容批二）：没有对应的系统应用图
    // 标可复刻，按设置里通知图标的视觉语汇自绘—
    // —红圆角底＋白色铃铛，不冒充任何 App 图标
    private var notificationsArtwork: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.22, style: .continuous
            )
            .fill(Color(hex: 0xFF3B30))
            .frame(width: size * 0.78, height: size * 0.78)
            Image(systemName: "bell.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    // 在场交互五件（设备扩容批三）：都无对应的系
    // 统应用图标可复刻（相机/翻译虽有系统应用，但
    // 这里的条目是「能力」不是那个应用本身），沿
    // 批二自绘语汇——彩色圆角底＋白色 SF 字形，不
    // 冒充任何 App 图标
    private var cameraArtwork: some View {
        glyphArtwork(
            colorHex: 0x48484A, symbol: "camera.fill", scale: 0.40
        )
    }

    private var visionArtwork: some View {
        glyphArtwork(
            colorHex: 0x00A79E, symbol: "text.viewfinder",
            scale: 0.42
        )
    }

    private var translateArtwork: some View {
        glyphArtwork(
            colorHex: 0x0A84FF, symbol: "translate", scale: 0.42
        )
    }

    private var ondeviceArtwork: some View {
        glyphArtwork(
            colorHex: 0xBF5AF2, symbol: "apple.intelligence",
            scale: 0.44
        )
    }

    private var biometricArtwork: some View {
        glyphArtwork(
            colorHex: 0x1C1C1E, symbol: "faceid", scale: 0.44
        )
    }

    // 日常面五件（设备扩容批四）：同样无对应的系统
    // 应用图标可复刻（定位/媒体库虽有系统应用，这
    // 里的条目是「能力」不是那个应用本身），沿批三
    // 自绘语汇——彩色圆角底＋白色 SF 字形
    private var locationArtwork: some View {
        glyphArtwork(
            colorHex: 0x0A84FF, symbol: "location.fill",
            scale: 0.42
        )
    }

    private var mediaArtwork: some View {
        glyphArtwork(
            colorHex: 0xFA2D48, symbol: "music.note",
            scale: 0.42
        )
    }

    private var composeArtwork: some View {
        glyphArtwork(
            colorHex: 0x64D2FF, symbol: "square.and.pencil",
            scale: 0.40
        )
    }

    private var shortcutsArtwork: some View {
        glyphArtwork(
            colorHex: 0x3A3A8C, symbol: "bolt.fill",
            scale: 0.42
        )
    }

    private var deviceinfoArtwork: some View {
        glyphArtwork(
            colorHex: 0x8E8E93, symbol: "iphone", scale: 0.42
        )
    }

    /// 彩底白字形瓷砖（批二通知/打开目标同款构图，
    /// 批三五件共用一个构造、不许各画一份走样）
    private func glyphArtwork(
        colorHex: UInt32, symbol: String, scale: CGFloat
    ) -> some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.22, style: .continuous
            )
            .fill(Color(hex: colorHex))
            .frame(width: size * 0.78, height: size * 0.78)
            Image(systemName: symbol)
                .font(.system(size: size * scale))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    // 打开目标（设备扩容批二）：同样无系统应用可
    // 复刻，靛蓝圆角底＋白色「跳出打开」字形自绘
    private var openerArtwork: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.22, style: .continuous
            )
            .fill(Color(hex: 0x5E5CE6))
            .frame(width: size * 0.78, height: size * 0.78)
            Image(systemName: "arrow.up.forward.app.fill")
                .font(.system(size: size * 0.40))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    // 照片：白底＋八片花瓣（系统照片应用的官方构
    // 图——放射状椭圆花瓣、每片半透明交叠；八色取
    // 官方采样序：黄/橙/红/粉/紫/蓝/青/绿，按宪法 §4
    // 「指称具体苹果系统应用时按官方构图复刻」的
    // 唯一例外行规矩）
    private var photosArtwork: some View {
        let petals: [(angle: Double, color: Color)] = [
            (0, Color(hex: 0xFFCC02)),
            (45, Color(hex: 0xFF9500)),
            (90, Color(hex: 0xFF3B30)),
            (135, Color(hex: 0xFF2D92)),
            (180, Color(hex: 0xAF52DE)),
            (225, Color(hex: 0x007AFF)),
            (270, Color(hex: 0x32ADE6)),
            (315, Color(hex: 0x34C759)),
        ]
        return ZStack {
            ForEach(Array(petals.enumerated()), id: \.offset) { _, petal in
                Ellipse()
                    .fill(petal.color.opacity(0.72))
                    .frame(width: size * 0.24, height: size * 0.52)
                    .offset(y: -size * 0.17)
                    .rotationEffect(.degrees(petal.angle))
            }
        }
        .frame(width: size, height: size)
    }

    // 活动（计步的系统归属「健身」应用）：白底＋同
    // 心三环（活动红/锻炼绿/站立青，官方三色）；
    // 环用圆弧近似——缺口朝右上，与官方构图同向
    private var motionArtwork: some View {
        let rings: [(radius: CGFloat, color: Color)] = [
            (0.40, Color(hex: 0xFA114F)),
            (0.28, Color(hex: 0xA6F750)),
            (0.16, Color(hex: 0x04C7DD)),
        ]
        return ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { _, ring in
                Circle()
                    .trim(from: 0.06, to: 0.94)
                    .stroke(
                        ring.color,
                        style: StrokeStyle(
                            lineWidth: size * 0.085,
                            lineCap: .round
                        )
                    )
                    .frame(
                        width: size * ring.radius * 2,
                        height: size * ring.radius * 2
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
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

    // 剪贴板（设备扩容批一）：没有对应的系统应用
    // 可复刻，按通用字形自绘——浅灰板身＋顶部夹子
    // ＋两行字线，中性灰、不冒充任何 App 图标
    private var clipboardArtwork: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.10, style: .continuous
            )
            .fill(Color(hex: 0xE9E9EE))
            .frame(width: size * 0.62, height: size * 0.74)
            RoundedRectangle(
                cornerRadius: size * 0.06, style: .continuous
            )
            .fill(Color(hex: 0xC7C7CC))
            .frame(width: size * 0.30, height: size * 0.13)
            .offset(y: -size * 0.36)
            VStack(spacing: size * 0.09) {
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: 0xAEAEB2))
                    .frame(width: size * 0.38, height: size * 0.07)
                RoundedRectangle(cornerRadius: size * 0.03)
                    .fill(Color(hex: 0xAEAEB2))
                    .frame(width: size * 0.30, height: size * 0.07)
            }
            .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
    }

    // 文件（设备扩容批一）：指称系统「文件」应用，
    // 按其官方构图复刻蓝文件夹——后板带左耳、前盖
    // 略浅，两层蓝（同 §4 复刻例外口径）
    private var filesArtwork: some View {
        let box = CGRect(
            x: size * 0.04, y: size * 0.08,
            width: size * 0.92, height: size * 0.84
        )
        return ZStack {
            folderBackPath(in: box).fill(Color(hex: 0x0A84FF))
            folderFrontPath(in: box).fill(Color(hex: 0x59ACFF))
        }
        .frame(width: size, height: size)
    }

    /// 文件夹后板（100×100 设计盒：左上凸耳＋主体）
    private func folderBackPath(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x / 100 * rect.width,
                y: rect.minY + y / 100 * rect.height
            )
        }
        var path = Path()
        path.move(to: pt(8, 80))
        path.addLine(to: pt(8, 28))
        path.addLine(to: pt(42, 28))
        path.addLine(to: pt(50, 38))
        path.addLine(to: pt(92, 38))
        path.addLine(to: pt(92, 80))
        path.closeSubpath()
        return path
    }

    /// 文件夹前盖（100×100 设计盒：上宽下窄的梯形）
    private func folderFrontPath(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + x / 100 * rect.width,
                y: rect.minY + y / 100 * rect.height
            )
        }
        var path = Path()
        path.move(to: pt(4, 46))
        path.addLine(to: pt(96, 46))
        path.addLine(to: pt(89, 84))
        path.addLine(to: pt(11, 84))
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
    /// 五件记录型数据集走「权限即同步」终形态
    /// （0.36.18）：状态头只出领头段；健康/家庭不
    /// 在此列、保持原双层呈现不动
    private var syncDataset: DeviceSyncDataset? {
        DeviceSyncDataset.fromSource(source)
    }

    /// 通道脚注（0.36.10，只剩健康/家庭用）：只由
    /// 本地可验事实拼——系统权限、调用开关、设备
    /// 会话在线三件，与目录行状态字同源同口径，不
    /// 许再出现 App 验不了的服务端状态宣称
    private var channelNote: String {
        guard permission.isUsable else {
            return "先在上方开好系统权限，智能体才有机会用这一件。"
        }
        guard controller.agentCallEnabled[source] ?? false else {
            return "调用开关已关：智能体问不到这一件，数据不会被调用。"
        }
        if controller.sessionOnline {
            return "设备会话在线：智能体发来调用时，这台手机现读现回。"
        }
        return "设备会话当前未连接：智能体现在叫不到这台手机；回到 App 前台、会话恢复在线后才可调用。"
    }

    var body: some View {
        Group {
            // 领头段（0.36.3，详情页语法五段式）：
            // 居中大真图标（苹果画法瓷砖 64）→名称→
            // 一句话说明。旧设置式分组头＋居中导航
            // 标题退役（对照授权页参考图）。
            // 0.36.18：记录型五件的副题换成副本口径
            // 一句（Core detailSubtitle）——副本在
            // 哪、谁来查、授权后自动同步，一句说清，
            // 本页不再出现第二段口径文字
            Section {
                VStack(spacing: OneDayMetrics.spacingS) {
                    DeviceAppIconView(source: source, size: 64)
                    Text(descriptor.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text(
                        syncDataset != nil
                            ? DeviceSyncPresentation.detailSubtitle
                            : descriptor.blurb
                    )
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OneDayMetrics.spacingSM)
            }
            .listRowBackground(Color.clear)

            if syncDataset == nil {
                // 健康/家庭（批二）保持原双层呈现不
                // 动：权限开关＋允许调用＋通道状态。
                // 剪贴板/文件（扩容批一）无系统权限：
                // 不画假的「系统权限」行，只剩调用开
                // 关这一个门，卡内一句说清区别
                Section {
                    if permission != .notApplicable {
                        permissionRow
                    }
                    Toggle(isOn: agentCallBinding) {
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
                    if permission == .notApplicable {
                        Text("这一件没有系统权限可开可关：这个开关就是唯一的门，关掉后智能体就读不到、也写不了。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
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
                    // 0.36.10（判词 3/4 口径统一）：脚
                    // 注由本地可验事实动态拼（channel-
                    // Note），与目录行 DeviceRowStatus
                    // 同源同口径；服务端状态 App 验不
                    // 了、不许写
                    Text(channelNote)
                }
                .listRowBackground(Palette.surface)
            }
            // 记录型五件：本组件到领头段为止——权限
            // 开关、状态字与日志由 DeviceSyncSection
            // 承接，授权区/通道状态区整组退役（用户
            // 00:03 定版：只剩一个开关）
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
                    case .notApplicable:
                        // 无系统权限两件不渲染权限行，
                        // 此臂仅为穷尽（不会走到）
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
struct DevicePermissionGate: View {
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
    /// 一步，不成段（续编 S11 空态句式同理）。
    /// 0.36.18：指路对象改成上方那一个权限开关
    /// 批二两件是动作型（设闹钟/发通知），未定文案
    /// 的动词随件走，不许拿「读取」糊弄动作权限
    private var gateVerb: String {
        switch source {
        case .alarm: return "设定"
        case .notifications: return "发送"
        case .camera: return "使用"
        default: return "读取"
        }
    }

    private var gateMessage: String {
        let name = DeviceSourceDirectory.descriptor(source).name
        switch permission {
        case .notDetermined:
            return "打开上方那一个开关，系统会问你是否允许\(gateVerb)\(name)。"
        case .denied, .restricted:
            return "打开上方那一个开关会跳到系统设置，在那里打开\(name)权限后即可。"
        case .writeOnly:
            return "当前只有写入权限，看不到已有安排。"
        default:
            return "当前状态下读不到数据。"
        }
    }
}

/// sheet 内禁用下拉刷新（0.36.5）：详情以 sheet
/// 呈现时下拉手势归 sheet 的交互式关闭——
/// refreshable 在场会先行截走下拉，用户 19:08 点
/// 名的「下拉返回不了」实因在此；push 呈现（设
/// 置页）无此冲突、保留下拉刷新。三页详情共用
struct RefreshableIfEnabled: ViewModifier {
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
            DeviceSyncSection(source: .calendar)
            if permission.isUsable {
                agendaSections
            } else {
                DevicePermissionGate(source: .calendar, permission: permission)
            }
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
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
        // 0.42.0：时刻走 DisplayDate 唯一格式器
        var text = event.isAllDay
            ? L10n.string("全天")
            : "\(DisplayDate.timeOnly(event.start)) – \(DisplayDate.timeOnly(event.end))"
        text += " · \(event.calendarName)"
        if let location = event.location, !location.isEmpty {
            text += " · \(location)"
        }
        return text
    }

    private func dayTitle(_ day: Date) -> String {
        // 0.42.0：「M月d日 星期X」走系统格式器字段
        // 拼装（钉界面语言、字段序随语言）；今天/明
        // 天前缀走目录模板
        let calendar = Calendar.current
        let style = Date.FormatStyle(
            locale: AppLocale.uiLocale, calendar: calendar,
            timeZone: calendar.timeZone
        )
        let styled = day.formatted(style.month().day().weekday(.wide))
        if calendar.isDateInToday(day) {
            return L10n.format("今天 · %@", styled)
        }
        if calendar.isDateInTomorrow(day) {
            return L10n.format("明天 · %@", styled)
        }
        return styled
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
            DeviceSyncSection(source: .reminders)
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
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
        // 0.42.0：日期时刻走 DisplayDate 绝对档；
        // 过期句模板走目录（键「已过期 %lld 天 · %@」
        // 等一组）
        let stamp = DisplayDate.absoluteDateTime(due)
        if item.isOverdue {
            let days = Calendar.current.dateComponents(
                [.day], from: due, to: Date()
            ).day ?? 0
            return days > 0
                ? L10n.format("已过期 %@ 天 · %@", String(days), stamp)
                : L10n.format("已过期 · %@", stamp)
        }
        return stamp
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
            DeviceSyncSection(source: .contacts)
            if permission.isUsable {
                contactsSections
            } else {
                DevicePermissionGate(
                    source: .contacts, permission: permission
                )
            }
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
                            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
    @State private var showDeleteAllConfirm = false
    @State private var deleteAllNote: String?

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
                Text("通讯录、日历、提醒、照片、步数这五件，进详情页只有一个权限开关：开着就自动同步、智能体能用，关要去系统设置里关。剪贴板与文件没有系统权限，详情页里的开关就是唯一的门。闹钟与通知有各自的系统权限，进详情页用开关开；打开目标同样没有系统权限。相机有系统权限，拍照与扫文档都要你当面操作；识别、翻译、端上智能与本人确认没有系统权限，开关就是唯一的门，其中端上智能只在支持的机型上出现。健康与家庭还差系统签名权益，开通前只列名、不显数据。")
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

            // 数据同步总览（0.36.14）：五件副本各一行
            // 状态字＋删除全部副本的总入口
            Section {
                ForEach(
                    DeviceSyncDataset.allCases, id: \.self
                ) { dataset in
                    NavigationLink {
                        detailDestination(dataset.sourceID)
                    } label: {
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            Text(dataset.label)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Spacer(
                                minLength: OneDayMetrics.spacingS
                            )
                            Text(syncSegment(dataset))
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                                .lineLimit(1)
                        }
                        .frame(
                            minHeight: OneDayMetrics
                                .settingsRowHeight
                        )
                    }
                }
                Button(role: .destructive) {
                    showDeleteAllConfirm = true
                } label: {
                    Text("删除全部同步副本")
                }
                if let deleteAllNote {
                    Text(deleteAllNote)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("数据同步")
            } footer: {
                Text("权限开着的件，整份清单自动同步一份在你自己的服务器上供智能体查；删副本只删服务器那一份，手机上的数据和系统权限都不动。权限还开着的话，下次打开 App 会自动重新同步回来。")
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
        .confirmationDialog(
            "删掉服务器上的全部同步副本？",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("删除全部副本", role: .destructive) {
                Task {
                    let ok = await appState.deviceSync
                        .deleteAllCopies(config: appState.config)
                    deleteAllNote = ok
                        ? "已删除。权限还开着的件，下次打开 App 会自动重新同步回来。"
                        : "没删成，检查服务器连接后再试。"
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删的是你服务器上的五份副本；手机上的数据、系统权限都不动。删完智能体就查不到这些清单了。")
        }
        .task {
            controller.refreshPermissions()
            await appState.deviceSync.refreshStatus(
                config: appState.config
            )
        }
    }

    private func syncSegment(_ dataset: DeviceSyncDataset) -> String {
        DeviceSyncPresentation.segment(
            dataset: dataset,
            status: appState.deviceSync.statuses[dataset],
            authorized: DeviceSyncControl.agentCanQuery(
                permission: controller.permissions[dataset.sourceID]
                    ?? .notDetermined
            ),
            now: Date()
        )
    }

    private func overviewRow(
        _ descriptor: DeviceSourceDescriptor
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            DeviceAppIconView(source: descriptor.sourceID, size: 40)
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
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
        let dataset = DeviceSyncDataset.fromSource(descriptor.sourceID)
        return DeviceRowStatus.line(
            descriptor: descriptor,
            permission: permission,
            agentCallEnabled:
                controller.agentCallEnabled[descriptor.sourceID] ?? false,
            sessionOnline: controller.sessionOnline,
            metric: nil,
            syncSegment: dataset.map { syncSegment($0) },
            // 照片/步数没有现读现回的通道，不拼调用态
            showsCallState: dataset == nil
                || descriptor.sourceID == .calendar
                || descriptor.sourceID == .reminders
                || descriptor.sourceID == .contacts
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
        case .photos: PhotosDetailView()
        case .motion: MotionDetailView()
        case .clipboard: ClipboardDetailView()
        case .files: FilesDetailView()
        case .alarm: AlarmDetailView()
        case .notifications: NotificationsDetailView()
        case .opener: OpenTargetDetailView()
        case .camera: CameraDetailView()
        case .vision: VisionDetailView()
        case .translate: TranslateDetailView()
        case .ondevice: OnDeviceDetailView()
        case .biometric: BiometricDetailView()
        case .location: LocationDetailView()
        case .media: MediaDetailView()
        case .compose: ComposeDetailView()
        case .shortcuts: ShortcutsDetailView()
        case .deviceinfo: DeviceInfoDetailView()
        case .health, .home: EmptyView()
        }
    }
}

// MARK: - 剪贴板详情（设备扩容批一）

/// 剪贴板详情：状态头（无系统权限行、只有调用开
/// 关）＋当前内容区。内容区不自动读剪贴板——读别
/// 家 App 的内容会触发系统粘贴提示，必须由用户亲
/// 手点按钮这一读才发生，文案如实说明
struct ClipboardDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var preview: String?
    @State private var previewNote: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .clipboard)
            Section {
                Text("这里不会自动读你的剪贴板。想看现在剪贴板里的文字，点下面的按钮现读一次——读取时系统可能弹出粘贴提示，这是苹果的规矩。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                Button("查看当前剪贴板文字") { readPreview() }
                if let preview {
                    Text(preview)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                } else if let previewNote {
                    Text(previewNote)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("当前内容")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func readPreview() {
        if let text = controller.dispatcher.clipboard.currentText() {
            preview = text.isEmpty ? "（剪贴板是空的）" : text
            previewNote = nil
        } else {
            preview = nil
            previewNote = "剪贴板里现在没有文字（可能是图片，或者本来就是空的）。"
        }
    }
}

// MARK: - 文件详情（设备扩容批一）

/// 文件详情：状态头＋本地文件夹浏览（只限 OneDay
/// 自己的文件夹，与工具同一引擎同一边界）。点文
/// 件夹下钻、点文件看文本预览；读不出（非文本/
/// 超限）如实显错误原文。本页不挂下拉刷新（sheet
/// 与 push 两路共用，下拉手势归 sheet 关闭——
/// 0.36.5 的教训），靠导航动作重读
struct FilesDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var currentPath = ""
    @State private var items: [DeviceFileItem] = []
    @State private var loadError: String?
    @State private var previewTitle: String?
    @State private var previewText: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .files)
            Section {
                if let loadError {
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                } else if items.isEmpty {
                    Text(
                        currentPath.isEmpty
                            ? "这个文件夹里还没有文件。智能体写入的文件会出现在这里。"
                            : "这个文件夹是空的。"
                    )
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
                }
                ForEach(items) { item in
                    fileRow(item)
                }
            } header: {
                headerText(
                    currentPath.isEmpty ? "根目录" : currentPath
                )
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)

            if !currentPath.isEmpty {
                Section {
                    Button("返回上一级") { goUp() }
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            }

            if let previewTitle {
                Section {
                    Text(previewTitle)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    if let previewText {
                        Text(previewText)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    headerText("预览")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { load() }
    }

    private func fileRow(_ item: DeviceFileItem) -> some View {
        Button {
            if item.isDirectory {
                currentPath = item.path
                previewTitle = nil
                previewText = nil
                load()
            } else {
                showPreview(item)
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(
                    systemName: item.isDirectory
                        ? "folder.fill" : "doc.text"
                )
                .foregroundStyle(
                    item.isDirectory
                        ? Color(hex: 0x0A84FF) : Palette.inkSecondary
                )
                .accessibilityHidden(true)
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    Text(item.name)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Text(subline(item))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func subline(_ item: DeviceFileItem) -> String {
        if item.isDirectory { return "文件夹" }
        let size = ByteCountFormatter.string(
            fromByteCount: item.sizeBytes, countStyle: .file
        )
        return "\(size) · \(DisplayDate.dateTime(item.modifiedAt))"
    }

    private func goUp() {
        let parts = currentPath.split(separator: "/")
        currentPath = parts.dropLast().joined(separator: "/")
        previewTitle = nil
        previewText = nil
        load()
    }

    private func load() {
        do {
            items = try controller.dispatcher.files.listItems(
                relativePath: currentPath
            )
            loadError = nil
        } catch let error as DeviceToolError {
            loadError = error.message
            items = []
        } catch {
            loadError = "读取文件夹失败"
            items = []
        }
    }

    private func showPreview(_ item: DeviceFileItem) {
        previewTitle = item.name
        do {
            previewText = try controller.dispatcher.files
                .readText(relativePath: item.path)
        } catch let error as DeviceToolError {
            previewText = error.message
        } catch {
            previewText = "读取文件失败"
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

// MARK: - 闹钟详情（设备扩容批二）

/// 闹钟详情：状态头＋系统闹钟列表（存在性与状态以
/// 系统列表为准，标题由本机登记表补）。行内「取
/// 消」是用户亲手的本地动作、不经桥；智能体设的
/// 闹钟与这里同表可见、对得上账
struct AlarmDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceAlarmItem] = []

    private var controller: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        controller.permissions[.alarm] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .alarm)
            if permission.isUsable {
                Section {
                    if items.isEmpty {
                        Text("现在没有待响的闹钟。在对话里让智能体按你的确认设定一个试试。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(
                                .vertical, OneDayMetrics.spacingS
                            )
                    }
                    ForEach(items) { item in
                        alarmRow(item)
                    }
                } header: {
                    headerText("已设的闹钟")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            } else {
                DevicePermissionGate(
                    source: .alarm, permission: permission
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { reload() }
    }

    private func alarmRow(_ item: DeviceAlarmItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(item.title ?? "闹钟")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Text(rowSubtitle(item))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            Button("取消") {
                controller.dispatcher.alarms.cancelLocal(
                    id: item.id
                )
                reload()
            }
            .font(.callout)
            .foregroundStyle(Palette.danger)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
    }

    private func rowSubtitle(_ item: DeviceAlarmItem) -> String {
        var parts: [String] = [
            item.isCountdown ? "倒计时" : "定点",
        ]
        if let fireAt = item.fireAt {
            parts.append(DisplayDate.dateTime(fireAt))
        }
        parts.append(item.stateText)
        return parts.joined(separator: " · ")
    }

    private func reload() {
        items = controller.dispatcher.alarms.currentItems()
    }
}

// MARK: - 通知详情（设备扩容批二）

/// 通知详情：状态头＋OneDay 自家待发通知列表（只
/// 认自家调度前缀，别家 App 的通知不在此列）。进
/// 页先异步刷新一次真权限状态再读列表——通知没
/// 有同步读法，刷新点收在本页与进前台两处（§113）
struct NotificationsDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceNotificationItem] = []

    private var controller: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        controller.permissions[.notifications] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .notifications)
            if permission.isUsable {
                Section {
                    if items.isEmpty {
                        Text("现在没有待发的通知。在对话里让智能体按你的确认发一条试试。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(
                                .vertical, OneDayMetrics.spacingS
                            )
                    }
                    ForEach(items) { item in
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(item.title)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            if !item.body.isEmpty {
                                Text(item.body)
                                    .font(.footnote)
                                    .foregroundStyle(
                                        Palette.inkSecondary
                                    )
                                    .lineLimit(2)
                            }
                            if let fireAt = item.fireAt {
                                Text(
                                    DisplayDate.dateTime(fireAt)
                                )
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                            }
                        }
                        .padding(
                            .vertical, OneDayMetrics.spacingMicro
                        )
                    }
                } header: {
                    headerText("待发的通知")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            } else {
                DevicePermissionGate(
                    source: .notifications,
                    permission: permission
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { await reload() }
    }

    private func reload() async {
        await NotificationEngine.readSystemState()
        controller.refreshPermissions()
        items = await controller.dispatcher.notifications
            .pendingItems()
    }
}

// MARK: - 打开目标详情（设备扩容批二）

/// 打开目标详情：状态头＋白名单全单。名单就是上
/// 限——智能体只能打开这些，名单之外没有任何入
/// 口；点任意一行是用户亲手打开试看（同一个执行
/// 引擎的本地路）
struct OpenTargetDetailView: View {
    @Environment(AppState.self) private var appState

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .opener)
            Section {
                ForEach(OpenTargetCatalog.all, id: \.id) { target in
                    Button {
                        controller.dispatcher.opener.openLocal(
                            target
                        )
                    } label: {
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            Text(
                                target.name(
                                    locale: AppLocale.uiLocale
                                )
                            )
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Text(
                                target.kind == .settings
                                    ? "系统设置" : "应用"
                            )
                            .font(.footnote)
                            .foregroundStyle(
                                Palette.inkSecondary
                            )
                            Image(systemName: "chevron.right")
                                .font(
                                    .footnote.weight(.semibold)
                                )
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                                .accessibilityHidden(true)
                        }
                        .frame(
                            minHeight: OneDayMetrics
                                .settingsRowHeight
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            } header: {
                headerText("可以打开的目标")
            } footer: {
                Text("智能体只能打开这一张名单里的目标，名单之外的链接一律打不开。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }
}

// MARK: - 相机详情（设备扩容批三）

/// 相机详情：状态头（真系统权限双层）＋已拍列表＋
/// 本地拍照按钮。列表只列 OneDay 文件夹 captures/
/// 里的产物（智能体拍的与在这里亲手拍的同处一列，
/// 以文件回读为准、不另记账）；本地按钮与工具走同
/// 一条引擎路（取景→落盘回读核对）
struct CameraDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceFileItem] = []
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .camera)
            Section {
                Button("现在拍一张") { captureLocal() }
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                if items.isEmpty {
                    Text("还没有拍过。智能体请你拍照、或你在这里亲手拍的，都会存到这里。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(items) { item in
                    HStack(
                        spacing: OneDayMetrics.spacingSM
                    ) {
                        Text(item.name)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Text(
                            DisplayDate.dateTime(item.modifiedAt)
                        )
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(
                        minHeight: OneDayMetrics.settingsRowHeight
                    )
                }
            } header: {
                headerText("拍过的照片与扫描")
            } footer: {
                Text("都在 OneDay 文件夹的 captures 里，文件页也能看到；不进系统相册。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { reload() }
    }

    private func reload() {
        items = controller.dispatcher.files.captureItems()
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func captureLocal() {
        Task {
            if controller.permissions[.camera] == .notDetermined {
                await controller.requestAccess(for: .camera)
            }
            do {
                let item = try await controller.dispatcher.camera
                    .captureAndSave()
                note = "已保存：\(item.name)"
                reload()
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

// MARK: - 识别详情（设备扩容批三）

/// 识别详情：状态头（无系统权限、单开关）＋本地试
/// 认区——列 captures/ 里的图片，点一张当场认文字
/// 给用户看（与工具同一条引擎路）。识别只在本地
/// 做，图不出手机，文案如实
struct VisionDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [DeviceFileItem] = []
    @State private var recognized: String?
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .vision)
            Section {
                if items.isEmpty {
                    Text("OneDay 文件夹里还没有图片。先用相机拍一张、或把图片放进文件夹，再回来认。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                ForEach(items) { item in
                    Button {
                        recognize(item)
                    } label: {
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            Text(item.name)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(
                                minLength: OneDayMetrics.spacingS
                            )
                            Text("认文字")
                                .font(.footnote)
                                .foregroundStyle(
                                    Palette.inkSecondary
                                )
                        }
                        .frame(
                            minHeight: OneDayMetrics
                                .settingsRowHeight
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
                if let recognized {
                    Text(recognized)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                } else if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("在这台手机上试认")
            } footer: {
                Text("识别在手机本地完成，图片不上传；智能体也是读同一批图片。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task {
            items = controller.dispatcher.files.captureItems()
                .sorted { $0.modifiedAt > $1.modifiedAt }
        }
    }

    private func recognize(_ item: DeviceFileItem) {
        Task {
            do {
                let result = try await controller.dispatcher.vision
                    .recognizeText(path: item.path)
                recognized = result.text.isEmpty
                    ? "（这张图里没认出文字）"
                    : result.text
                note = nil
            } catch let error as DeviceToolError {
                note = error.message
                recognized = nil
            } catch {
                note = error.localizedDescription
                recognized = nil
            }
        }
    }
}

// MARK: - 翻译详情（设备扩容批三）

/// 翻译详情：状态头（无系统权限、单开关）＋常用语
/// 言对的下载状态（LanguageAvailability 现查）：
/// 没下载的组合翻不了、如实列明，免得用户对着工
/// 具报错才知道差语言包
struct TranslateDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var rows: [(label: String, status: String)] = []

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    private static let pairs: [(String, String, String)] = [
        ("en", "zh-Hans", "英语 → 简体中文"),
        ("zh-Hans", "en", "简体中文 → 英语"),
        ("ja", "zh-Hans", "日语 → 简体中文"),
        ("ko", "zh-Hans", "韩语 → 简体中文"),
        ("zh-Hant", "zh-Hans", "繁体中文 → 简体中文"),
    ]

    var body: some View {
        List {
            DeviceStatusHeader(source: .translate)
            Section {
                ForEach(
                    Array(rows.enumerated()), id: \.offset
                ) { _, row in
                    HStack(
                        spacing: OneDayMetrics.spacingSM
                    ) {
                        Text(row.label)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Text(row.status)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(
                        minHeight: OneDayMetrics.settingsRowHeight
                    )
                }
            } header: {
                headerText("常用语言对")
            } footer: {
                Text("语言包在系统「翻译」里管理：没下载的组合，先去那里把语言包下载好就能翻。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { await reload() }
    }

    private func reload() async {
        var loaded: [(label: String, status: String)] = []
        for (source, target, label) in Self.pairs {
            let status = await controller.dispatcher.translate.status(
                from: Locale.Language(identifier: source),
                to: Locale.Language(identifier: target)
            )
            loaded.append(
                (label, TranslateEngine.statusText(status))
            )
        }
        rows = loaded
    }
}

// MARK: - 端上智能详情（设备扩容批三）

/// 端上智能详情：状态头（无系统权限、单开关）＋可
/// 用性一行（机型事实现读：可用/不支持/未开启/
/// 未就绪逐档如实）。不可用时机型上这一件不会进
/// 智能体的可调用清单，详情页把原因写明
struct OnDeviceDetailView: View {
    var body: some View {
        List {
            DeviceStatusHeader(source: .ondevice)
            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("这台手机")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(OnDeviceModelEngine.availabilityLine())
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                headerText("可用状态")
            } footer: {
                Text("每次调用都是一次单次问答，不记上文；回答在本机生成，不联网。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }
}

// MARK: - 本人确认详情（设备扩容批三）

/// 本人确认详情：状态头（无系统权限开关——同意在
/// 每次验证时由系统当面给出）＋识别方式一行＋本
/// 地试一次按钮（与工具同一条引擎路，让用户先亲
/// 手看看系统验证框长什么样、理由写在哪）
struct BiometricDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .biometric)
            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("验证方式")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(BiometricEngine.biometryKindText())
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                Button("试一次本人确认") { tryLocal() }
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("在这台手机上试一次")
            } footer: {
                Text("系统只回「过没过」；你的面容或指纹数据永远不出系统，OneDay 碰不到。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func tryLocal() {
        Task {
            do {
                let result = try await controller.dispatcher.biometric
                    .confirm(
                        BiometricAuthArgs(
                            reason: "在 OneDay 里试一次本人确认"
                        )
                    )
                if case .object(let object) = result,
                   case .bool(let confirmed)? =
                    object["confirmed"] {
                    note = confirmed
                        ? "已确认：是你本人。"
                        : "这次没有确认通过。"
                }
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

// MARK: - 定位详情（设备扩容批四）

/// 定位详情：状态头（真系统权限、权限开关终形态）
/// ＋本地试一次区——亲手点一次现读当前位置，把地
/// 名与精度如实显出来（与工具同一条引擎路）。没
/// 有后台定位这回事，文案与名册口径一致
struct LocationDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        controller.permissions[.location] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .location)
            if permission.isUsable {
                Section {
                    Button("看看我现在在哪") { locateLocal() }
                    if let note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                } header: {
                    headerText("在这台手机上试一次")
                } footer: {
                    Text("只现读这一次，不做后台定位、不存位置副本。")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            } else {
                DevicePermissionGate(
                    source: .location, permission: permission
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func locateLocal() {
        Task {
            do {
                let result = try await controller.dispatcher
                    .location.currentResult(LocationCurrentArgs())
                if case .object(let object) = result {
                    let place = object["placeName"]?.stringValue
                        ?? object["address"]?.stringValue
                    var accuracyText = ""
                    if case .number(let meters)? =
                        object["accuracyMeters"] {
                        accuracyText =
                            "（精度约 \(Int(meters.rounded())) 米）"
                    }
                    note = (place ?? "已读到坐标，但没查到地名")
                        + accuracyText
                }
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

// MARK: - 媒体库详情（设备扩容批四）

/// 媒体库详情：状态头（真系统权限）＋播放状态一
/// 行（本地现读）＋歌单区（与工具同一引擎：名＋
/// 首数）。检索面不在详情页复刻，详情页只给用户
/// 一个「我的资料库大概什么样」的本地事实面
struct MediaDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var playbackLine: String?
    @State private var playlists: [[String: JSONValue]] = []
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }
    private var permission: DevicePermissionState {
        controller.permissions[.media] ?? .notDetermined
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .media)
            if permission.isUsable {
                Section {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text("系统音乐播放器")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Text(playbackLine ?? "读取中")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(
                        minHeight: OneDayMetrics.settingsRowHeight
                    )
                } header: {
                    headerText("播放状态")
                } footer: {
                    Text("这里只看系统音乐播放器的状态；其他 App 在放什么，系统不给读。")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)

                Section {
                    if let note {
                        Text(note)
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if playlists.isEmpty && note == nil {
                        Text("资料库里还没有歌单。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    ForEach(
                        Array(playlists.enumerated()),
                        id: \.offset
                    ) { _, playlist in
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            Text(
                                playlist["name"]?.stringValue ?? ""
                            )
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            Spacer(
                                minLength: OneDayMetrics.spacingS
                            )
                            Text(
                                "\(playlist["itemCount"]?.displayString ?? "") 首"
                            )
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        }
                        .frame(
                            minHeight: OneDayMetrics
                                .settingsRowHeight
                        )
                    }
                } header: {
                    headerText("我的歌单")
                }
                .listRowBackground(Palette.surface)
                .listRowInsets(deviceRowInsets)
            } else {
                DevicePermissionGate(
                    source: .media, permission: permission
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { await reload() }
    }

    private func reload() async {
        playbackLine = await controller.dispatcher.media
            .localPlaybackLine()
        do {
            playlists = try controller.dispatcher.media
                .localPlaylists()
            note = nil
        } catch let error as DeviceToolError {
            note = error.message
        } catch {
            note = error.localizedDescription
        }
    }
}

// MARK: - 拨号与撰写详情（设备扩容批四）

/// 拨号与撰写详情：状态头（无系统权限、单开关）
/// ＋本地试一次区——空预填打开短信/邮件撰写面，
/// 让用户先亲眼看看智能体能递到手上的是什么面；
/// 发出永远是用户在面上亲手点的事，文案钉死
struct ComposeDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .compose)
            Section {
                Button("试着写一条短信") { trialSMS() }
                Button("试着写一封邮件") { trialMail() }
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("在这台手机上试一次")
            } footer: {
                Text("打开的是空撰写面，收件人和内容都由你亲手填；智能体也只能做到把预填好的面递到你手上，发不发由你在面上点。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func trialSMS() {
        Task {
            do {
                let outcome = try await controller.dispatcher
                    .compose.trialSMS()
                note = Self.outcomeText(outcome)
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func trialMail() {
        Task {
            do {
                let outcome = try await controller.dispatcher
                    .compose.trialMail()
                note = Self.outcomeText(outcome)
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private static func outcomeText(
        _ outcome: ComposeOutcome
    ) -> String {
        switch outcome {
        case .sent: return "已由你亲手发出。"
        case .savedDraft: return "你把这封邮件存成了草稿，没有发。"
        case .cancelled: return "你取消了，没有发出。"
        }
    }
}

// MARK: - 快捷指令详情（设备扩容批四）

/// 快捷指令详情：状态头（无系统权限、单开关）＋
/// 本地运行区——系统不给枚举，只能按名运行：用
/// 户亲手填一个名字运行一次，既是试用、也是给智
/// 能体对名字的唯一办法（名字对不对当场见分晓）
struct ShortcutsDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var name = ""
    @State private var note: String?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .shortcuts)
            Section {
                TextField("快捷指令的名字", text: $name)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Button("运行这一条") { runLocal() }
                    .disabled(
                        name.trimmingCharacters(
                            in: .whitespaces
                        ).isEmpty
                    )
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } header: {
                headerText("按名运行")
            } footer: {
                Text("系统没有列出全部快捷指令的办法，只能按名字运行你已经建好的一条；运行会切到快捷指令去执行。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func runLocal() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                let outcome = try await controller.dispatcher
                    .shortcuts.runLocal(name: trimmed)
                switch outcome {
                case .success(let result):
                    note = result.map {
                        "运行完了，它回的内容是：\($0)"
                    } ?? "运行完了。"
                case .cancelled:
                    note = "你在快捷指令那边取消了运行。"
                case .failed(let message):
                    note = message.map {
                        "快捷指令那边回了出错：\($0)"
                    } ?? "快捷指令那边回了出错。"
                case .noCallback:
                    note = "已发起运行，但一直没等到回执，不确认它跑没跑完。"
                }
            } catch let error as DeviceToolError {
                note = error.message
            } catch {
                note = error.localizedDescription
            }
        }
    }
}

// MARK: - 设备信息详情（设备扩容批四）

/// 设备信息详情：状态头（无系统权限、单开关）＋
/// 本地现读区——机型/系统/电量/存储/网络逐行如
/// 实列（与工具同一份快照）。读不到的项显「未知」
/// 原样，不编
struct DeviceInfoDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var snapshot: DeviceInfoSnapshot?

    private var controller: DeviceSessionController {
        appState.deviceSession
    }

    var body: some View {
        List {
            DeviceStatusHeader(source: .deviceinfo)
            Section {
                if let snapshot {
                    infoRow("机型标识", snapshot.modelIdentifier)
                    infoRow(
                        "系统",
                        "\(snapshot.systemName) \(snapshot.systemVersion)"
                    )
                    infoRow(
                        "电量",
                        snapshot.batteryPercent.map {
                            "\($0)% · \(snapshot.batteryStateText)"
                        } ?? "未知"
                    )
                    infoRow(
                        "低电量模式",
                        snapshot.lowPowerMode ? "开" : "关"
                    )
                    infoRow(
                        "存储还剩",
                        Self.bytesText(snapshot.storageFreeBytes)
                            + "（共 "
                            + Self.bytesText(snapshot.storageTotalBytes)
                            + "）"
                    )
                    infoRow("当前网络", snapshot.networkText)
                } else {
                    Text("读取中")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Button("重新读一次") { reload() }
            } header: {
                headerText("这台手机现在")
            } footer: {
                Text("全部现读现回、不存副本；手机的名字与当前 Wi-Fi 名称需要签名权益才读得到，不在此列。")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(deviceRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .task { reload() }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
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

    private func reload() {
        Task {
            snapshot = await controller.dispatcher.deviceInfo
                .snapshot()
        }
    }

    private static func bytesText(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }
}
