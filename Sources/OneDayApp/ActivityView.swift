import SwiftUI

/// 活动格（0.6.0 一期，蓝图 §4）：枢纽页转正的唯一承载——
/// 内容就是 AgentHubView 的活动/审核两段（活动流拼装＋
/// write-gate 待批卡），全 App 只此一份实现；聊天页胶囊
/// 点按改道本格，不再开 sheet。审批终态后回调刷新总览
/// 桥，顶栏角标不等下一轮轮询。
struct ActivityView: View {
    let overviewStore: OverviewBridgeStore

    @Environment(AppState.self) private var appState

    var body: some View {
        AgentHubView(mode: .activity, onApprovalChanged: {
            Task { await overviewStore.refresh(appState: appState) }
        })
    }
}
