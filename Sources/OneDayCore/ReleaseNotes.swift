import Foundation

/// App 更新说明（台账 175，OB-U3 App 侧；DESIGN §391）：
/// 随包发布的版本说明表——关于页「更新说明」段的数据源。
/// 口径：条目只记已发货版本的人话要点（出处＝各版组版
/// 记账 DESIGN §376–§378 与发货事实），不记未发货内容；
/// 新版组版时在表头加一条。服务端更新感知归 H12 只读面
/// （§360，执行在运维侧），本表只管 App 自身版本说明。
public struct ReleaseNoteEntry: Equatable, Sendable, Identifiable {
    /// 版本号（与 CFBundleShortVersionString 同形）
    public let version: String
    /// 要点行（人话，每行一条）
    public let highlights: [String]

    public var id: String { version }

    public init(version: String, highlights: [String]) {
        self.version = version
        self.highlights = highlights
    }
}

public enum ReleaseNotes {
    /// 全部条目（新 → 旧）
    public static let entries: [ReleaseNoteEntry] = [
        ReleaseNoteEntry(version: "0.50.98", highlights: [
            "聊天列表换引擎收官：消息按变化增量更新，长会话滑动与落定更跟手",
            "发送与落定结清拆拍，停滚后内容追平更快",
            "旧消息承载整套退役，安装包更小",
        ]),
        ReleaseNoteEntry(version: "0.50.97", highlights: [
            "消息列表改单列构造，行高按消息精确计算，长会话上翻更稳",
        ]),
        ReleaseNoteEntry(version: "0.50.96", highlights: [
            "消息增量更新转正：新消息到达只算变化的那几行",
            "资源库与抽屉打开提速",
        ]),
        ReleaseNoteEntry(version: "0.50.95", highlights: [
            "资源库名单先用快照上屏、再悄悄对账刷新，进面不再空等",
            "抽屉名单、模型目录等名单加新鲜度门，过期自动重拉",
        ]),
        ReleaseNoteEntry(version: "0.50.94", highlights: [
            "修复启动闪退（界面结构减深）",
        ]),
    ]

    /// 指定版本的条目（表里没有返回 nil，不编造）
    public static func entry(forVersion version: String) -> ReleaseNoteEntry? {
        entries.first { $0.version == version }
    }

    /// 当前版本条目＋此前的条目（关于页呈现序：当前在首、
    /// 其余按表序）；当前版本不在表中时只返回全表（不冒充）
    public static func entries(
        currentVersion: String
    ) -> [ReleaseNoteEntry] {
        guard let current = entry(forVersion: currentVersion) else {
            return entries
        }
        return [current] + entries.filter { $0.version != currentVersion }
    }
}
