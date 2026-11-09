import Foundation

/// 底栏符号名对（0.3.1 礼记同款立，0.4.0 续）：
/// 0.4.0 底栏回原生 TabView（审计 §3.2），本表是原生
/// Tab 的 Label 符号源（数据保留，§1.2 #28）：符号由
/// 系统直渲（零预渲染，0.2.9 路线作废口径不变）。
/// selected 恒等于 normal（§22.5 禁 .fill 口径），
/// 选中态由系统玻璃坞呈现。本表是底栏符号名的单一
/// 事实源，单测钉死。0.6.0 五格 IA（移植蓝图 §4 一
/// 期）：聊天／活动／点子／目标／应用，符号按 OpenMuse
/// 五格近似对位。两处按量测止损换体（0.4.5 路线，CI
/// 42575859938 实测）：活动原定 list.bullet.rectangle
/// 名单密度 0.516/紧致 0.467、应用原定 square.grid.2x2
/// 名单密度 0.541/紧致 0.505，同出线条画法档（≤0.45/
/// ≤0.42），且应用格 .fill 变体另与 §22.5 禁 fill 冲
/// 突——活动换 list.bullet（枢纽页活动段既有符号、同
/// 源），应用换 apps.iphone（官方 apps 命名、细线轮
/// 廓）；不许放宽量测闸迁就符号（口径差在 0.6.0 回执）。
/// 0.4.5 换本体（§30.7，用户 11:49 点名）：0.4.1/
/// 0.4.3 两轮「锁 outline 变体」都没过真机（文件、
/// 聊天两格仍实心观感），按止损换路——符号本体直
/// 接换线条画法：聊天 bubble.left.and.bubble.right
/// （双泡叠合轮廓）→message（单泡＋横线）；文件
/// folder（闭合轮廓）→tray（开口托盘线条）；总览
/// chart.line.uptrend.xyaxis→chart.xyaxis.line（带
/// 轴折线、三口径最轻）；设置 slider.horizontal.3
/// 留。选型以墨迹密度量测为闸（RenderMeasureTests
/// 同口径对照，数值与口径辨析见 §30.7）；变体锁
/// （.symbolVariants .none）保留作第二道防线。
public struct TabSymbolPair: Equatable, Sendable {
    /// 条目标识（与无障碍标识 tab.<id> 共用）
    public let id: String
    /// 栏内标题（礼记同款：标题随 Label 进栏）
    public let title: String
    /// 未选态符号名（线条体）
    public let normal: String
    /// 选中态符号名（官方 .fill 对；无对时与 normal 同名）
    public let selected: String

    public init(id: String, title: String, normal: String, selected: String) {
        self.id = id
        self.title = title
        self.normal = normal
        self.selected = selected
    }

    /// 按选中态取符号名
    public func name(isSelected: Bool) -> String {
        isSelected ? selected : normal
    }
}

/// 五个底栏条目的符号名对（顺序与 ContentView 条目同序）
public enum TabBarSymbols {
    public static let chat = TabSymbolPair(
        id: "chat", title: "聊天",
        normal: "message",
        selected: "message"
    )
    public static let activity = TabSymbolPair(
        id: "activity", title: "活动",
        normal: "list.bullet",
        selected: "list.bullet"
    )
    public static let ideas = TabSymbolPair(
        id: "ideas", title: "点子",
        normal: "lightbulb",
        selected: "lightbulb"
    )
    public static let goals = TabSymbolPair(
        id: "goals", title: "目标",
        normal: "checklist",
        selected: "checklist"
    )
    public static let apps = TabSymbolPair(
        id: "apps", title: "应用",
        normal: "apps.iphone",
        selected: "apps.iphone"
    )

    // 旧三格符号保留作应用格内入口行与抽屉名单的符号源
    // （总览/文件/设置自 0.6.0 起是应用格内的页面，不再
    // 占底栏格；符号本体口径不变）
    public static let overview = TabSymbolPair(
        id: "overview", title: "总览",
        normal: "chart.xyaxis.line",
        selected: "chart.xyaxis.line"
    )
    public static let files = TabSymbolPair(
        id: "files", title: "文件",
        normal: "tray",
        selected: "tray"
    )
    public static let settings = TabSymbolPair(
        id: "settings", title: "设置",
        normal: "slider.horizontal.3",
        selected: "slider.horizontal.3"
    )

    /// 全部条目（与 ContentView 的 Tab 顺序同序）
    public static let all = [chat, activity, ideas, goals, apps]
}
