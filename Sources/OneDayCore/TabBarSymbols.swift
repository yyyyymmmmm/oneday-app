import Foundation

/// 底栏符号名对（0.3.1 礼记同款立，0.4.0 续）：
/// 0.4.0 底栏回原生 TabView（审计 §3.2），本表是原生
/// Tab 的 Label 符号源（数据保留，§1.2 #28）：符号由
/// 系统直渲（零预渲染，0.2.9 路线作废口径不变）。四
/// 格 selected 恒等于 normal（§22.5 禁 .fill 口径），
/// 选中态由系统玻璃坞呈现。本表是四格符号名的单一
/// 事实源，单测钉死。
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
        selected: "bubble.left.and.bubble.right"
    )
    public static let overview = TabSymbolPair(
        id: "overview", title: "总览",
        normal: "chart.line.uptrend.xyaxis",
        selected: "chart.line.uptrend.xyaxis"
    )
    public static let files = TabSymbolPair(
        id: "files", title: "文件",
        normal: "folder",
        selected: "folder"
    )
    public static let settings = TabSymbolPair(
        id: "settings", title: "设置",
        normal: "slider.horizontal.3",
        selected: "slider.horizontal.3"
    )

    /// 全部条目（与 ContentView 的 Tab 顺序同序）
    public static let all = [chat, overview, files, settings]
}
