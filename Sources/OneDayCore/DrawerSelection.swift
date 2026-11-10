import Foundation

/// 抽屉当前对象引用（0.36.7，频道规格
/// channels-conversations-design §10.2/§10.3）：全
/// 抽屉唯一选择源的显式通道载荷——「当前正在看的
/// 对象」三形：主线、某条旁聊、某频道（0.36.29 频
/// 道包在本政策上加值扩展，与 0.36.7 三值版同政策
/// 同解析、不另起一套）。写入点只有导航动作（抽
/// 屉主线行/旁聊行点按、频道页打开会话）与 Chat-
/// View 的当前线程同步（落点解析/切换/新建/导入
/// 完成都经它；频道出处由 ChannelViewingOrigin 维
/// 护、同步时优先于线程派生），页签切走不清（回
/// 切时恢复）。
public enum DrawerCurrentObject: Equatable, Sendable {
    case main
    case side(UUID)
    /// 正在看的会话来自某频道（经频道页点开，在
    /// ChatView 呈现期间成立——即便该会话已被收养
    /// 导入成本地线程渲染，分类归属与选择归属是两
    /// 件事，见频道规格 §10.2）
    case channel(String)
}

/// 频道观看出处（0.36.29，§10.2/§10.3）：「当前线
/// 程是从哪个频道的哪条会话打开的」——ChatView
/// 当前线程同步据此把对象引用维持在 .channel，
/// 而非随导入线程派生成 .side。置位点只有频道打
/// 开会话的消费口（consumePendingChatSession）；
/// 线程切离该会话（切别的线程/新建/从旁聊区重进
/// 同一条）即失效，由各置位点清除。
public struct ChannelViewingOrigin: Equatable, Sendable {
    public let channelID: String
    public let sessionID: String

    public init(channelID: String, sessionID: String) {
        self.channelID = channelID
        self.sessionID = sessionID
    }
}

/// 抽屉选择解析结果（§10.2 值域：0.36.7 三值＋
/// 0.36.29 频道加值＋空态）：任一时刻至多一行带
/// 胶囊。空态 .none 只出现在聊天表面且当前对象
/// 与落点都无从派生时（无线程的极端情形），不画
/// 假当前。
public enum DrawerSelection<Tab: Equatable & Sendable>:
    Equatable, Sendable
{
    /// 当前表面为非聊天页签：胶囊归该导航行，
    /// 所有会话行无胶囊（会话选择休眠）
    case surface(Tab)
    /// 正在看主线：胶囊归「主线聊天」行
    case main
    /// 正在看某条旁聊：胶囊只归该旁聊行
    case side(UUID)
    /// 正在看的会话来自某频道（0.36.29 加值）：胶
    /// 囊归该频道行，主线聊天行、旁聊行皆无胶囊
    case channel(String)
    /// 无从派生（见上）
    case none
}

/// 抽屉单一选择政策（§10.2）：抽屉任何行禁止再私
/// 读 currentTab／activeThreadID 自行画胶囊，一律
/// 问本政策。底栏不在辖区（底栏高亮表达表面、与
/// 抽屉内的对象选择是两件事）。
public enum DrawerSelectionPolicy {
    /// 解析优先级（§10.2）：①表面非聊天→.surface；
    /// ②有显式当前对象引用→按引用；③无引用→按落
    /// 点线程派生（与 ChatLandingResolution 落点同
    /// 源同果：落主线→.main、落旁聊→.side）；④皆
    /// 无→.none
    public static func resolve<Tab: Equatable & Sendable>(
        currentTab: Tab,
        chatTab: Tab,
        currentObject: DrawerCurrentObject?,
        landingThreadID: UUID?,
        mainThreadID: UUID?
    ) -> DrawerSelection<Tab> {
        if currentTab != chatTab {
            return .surface(currentTab)
        }
        if let currentObject {
            switch currentObject {
            case .main: return .main
            case .side(let id): return .side(id)
            case .channel(let id): return .channel(id)
            }
        }
        if let landingThreadID {
            return landingThreadID == mainThreadID
                ? .main
                : .side(landingThreadID)
        }
        return .none
    }

    /// 由线程 id 派生对象引用（ChatView 当前线程同
    /// 步点专用：钦定主线→.main、其余→.side、无线
    /// 程→nil 清引用）
    public static func object(
        forThreadID id: UUID?, mainThreadID: UUID?
    ) -> DrawerCurrentObject? {
        guard let id else { return nil }
        return id == mainThreadID ? .main : .side(id)
    }
}
