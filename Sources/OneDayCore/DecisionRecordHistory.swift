import Foundation

/// 已决记录合并（§259，2026-11-14 通知单源化）：审批
/// 已决记录有两扇拉取窗口——日常近窗（最近 50 条、
/// 每轮刷新）与锚点回溯宽窗（500 条/30 天、低频刷
/// 新）。此前合成散在三处消费点各自现拼（两处 View
/// 层、一处 store 内），同一本账三种拼法。此后合
/// 成只此一处：近窗在前（同 id 以近窗为准——近窗
/// 拉取更新、内容以新为准），宽窗补近窗没有的，
/// 保入序不重排。消费方（通知落点查账、台账详情、
/// 锚点行态、锚点物化）一律读合成结果，不许再自拼。
public enum DecisionRecordHistory {
    public static func merge(
        recent: [WriteGateDecisionRecord],
        wide: [WriteGateDecisionRecord]?
    ) -> [WriteGateDecisionRecord] {
        guard let wide else { return recent }
        let recentIDs = Set(recent.map(\.id))
        return recent + wide.filter { !recentIDs.contains($0.id) }
    }
}
