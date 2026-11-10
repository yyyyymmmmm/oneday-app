import Foundation

/// 抽屉当前对象引用（0.36.7，频道规格
/// channels-conversations-design §10.2/§10.3）：全
/// 抽屉唯一选择源的显式通道载荷——「当前正在看的
/// 对象」只有主线与某条旁聊两形（频道值 .channel
/// 留 0.36.9 在本政策上加值扩展，本版不先行）。
/// 写入点只有导航动作（抽屉主线行/旁聊行点按）与
/// ChatView 的当前线程同步（落点解析/切换/新建/
/// 导入完成都经它），页签切走不清（回切时恢复）。
public enum DrawerCurrentObject: Equatable, Sendable {
    case main
    case side(UUID)
}

/// 抽屉选择解析结果（§10.2 值域三值＋空态）：任一
/// 时刻至多一行带胶囊。空态 .none 只出现在聊天表
/// 面且当前对象与落点都无从派生时（无线程的极端
/// 情形），不画假当前。
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
