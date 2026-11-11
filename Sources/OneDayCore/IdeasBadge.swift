import Foundation

/// 点子底栏角标的增量判定（§123 M3，闭环包）：动态角标
/// 有服务端未读账，点子没有——桥的点子读面只有全量列
/// 表。本枚举在既有读面之上做本地增量判定：
///
/// - 「新卡」＝生成卡（source == .generated）且待阅
///   （status == .pending）且 createdAt 晚于水位；
///   手记卡是用户自己写的，不给自己报新；已采纳/已
///   忽略的卡不在待阅面，不算新；
/// - 水位＝用户上次打开点子页时已知的最新生成卡时刻，
///   本地落盘（AppState），进页即推进、角标即清——与
///   动态角标「进页即清」同口径；
/// - 首次无水位（新装/首启）时只立基线不报数：存量
///   卡不是「刚到的」，不许一装上就挂一排假角标。
public enum IdeasBadge {
    public static func newCount(
        ideas: [BridgeIdea], watermark: Double?
    ) -> Int {
        guard let watermark else { return 0 }
        return ideas.filter {
            $0.source == .generated
                && $0.status == .pending
                && $0.createdAt > watermark
        }.count
    }

    /// 水位推进到当前已知的最新生成卡时刻（任何状态的
    /// 生成卡都算「已经见过」——采纳/忽略动作本身就发
    /// 生在点子页里）；无生成卡时保持原水位
    public static func advancedWatermark(
        ideas: [BridgeIdea], current: Double?
    ) -> Double? {
        let newest = ideas
            .filter { $0.source == .generated }
            .map(\.createdAt)
            .max()
        switch (current, newest) {
        case let (c?, n?): return max(c, n)
        case let (c?, nil): return c
        case let (nil, n?): return n
        case (nil, nil): return nil
        }
    }
}
