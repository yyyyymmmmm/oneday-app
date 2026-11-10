import Foundation

/// 聊天页签落点解析（0.30.0，用户 2026-11-10 12:56
/// 录屏讲解 Muse 模型）：底部「会话」页签不与主线
/// 绑定——不管当前在主聊还是旁聊，点页签/冷启回到
/// 的都是上次停留的那条对话；抽屉「主线聊天」行是
/// 唯一显式回主线入口（它经线程选择通道直切钦定主
/// 线，不经本解析）。
///
/// 本解析只管「无显式改道时落哪条」：进程内已在某
/// 线程（页签切走再切回）时保持不动；冷启/视图重建
/// 时恢复上次线程；上次线程已不存在则回主线；三者
/// 均不在名单内则无落点（调用方走既有空态兜底）。
public enum ChatLandingResolution {
    public enum Decision: Equatable, Sendable {
        /// 进程内当前线程仍在名单内，保持不动（页签切换）
        case keep(UUID)
        /// 恢复上次停留线程（冷启/视图重建）
        case restore(UUID)
        /// 回钦定主线（无上次纪录或记录已失效）
        case main(UUID)
        /// 当前/上次/主线均不在名单内，无落点
        case none
    }

    public static func landing(
        currentID: UUID?,
        lastThreadID: UUID?,
        existingIDs: some Collection<UUID>,
        mainThreadID: UUID?
    ) -> Decision {
        if let currentID, existingIDs.contains(currentID) {
            return .keep(currentID)
        }
        if let lastThreadID, existingIDs.contains(lastThreadID) {
            return .restore(lastThreadID)
        }
        if let mainThreadID, existingIDs.contains(mainThreadID) {
            return .main(mainThreadID)
        }
        return .none
    }
}
