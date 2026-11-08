import Foundation

/// 底栏符号名对（0.3.1 礼记同款，DESIGN-V4 §16）：
/// 图标由系统按 Label(systemImage:) 直渲——零尺寸
/// 配置、零预渲染（0.2.9 烘焙定标与配置定标路线均
/// 已作废删除）。本表是四个 tab 的「未选线条体 ↔
/// 选中 .fill」官方成对变体的单一事实源：bubble 与
/// folder 有官方 .fill 对；chart.line.uptrend.xyaxis
/// 与 slider.horizontal.3 目录内无 .fill 变体，选中
/// 同名（只吃 .bounce 区分状态）。单测钉死本表。
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

/// 四个底栏条目的符号名对（顺序与 ContentView 条目同序）
public enum TabBarSymbols {
    public static let chat = TabSymbolPair(
        id: "chat", title: "聊天",
        normal: "bubble.left.and.bubble.right",
        selected: "bubble.left.and.bubble.right.fill"
    )
    public static let overview = TabSymbolPair(
        id: "overview", title: "总览",
        normal: "chart.line.uptrend.xyaxis",
        selected: "chart.line.uptrend.xyaxis"
    )
    public static let files = TabSymbolPair(
        id: "files", title: "文件",
        normal: "folder",
        selected: "folder.fill"
    )
    public static let settings = TabSymbolPair(
        id: "settings", title: "设置",
        normal: "slider.horizontal.3",
        selected: "slider.horizontal.3"
    )

    /// 全部条目（与 ContentView 的 Tab 顺序同序）
    public static let all = [chat, overview, files, settings]
}
