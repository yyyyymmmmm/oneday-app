import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页浏览器段（规格 §3.3，用户定案：留口）：段位
/// 保留、内容只有系统空态＋一行 computer-use 就绪状态。
/// 不显示任务计数、不放 + 钮、不生成任务行——后端任务
/// 记录接口不存在，任何计数表达都是冒充（数据设计 §6）。
struct HubBrowserSection: View {
    let store: AgentHubStore

    var body: some View {
        switch store.browserState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .statusOnly, .failed:
            ContentUnavailableView {
                Label("暂无浏览器任务", systemImage: "display")
            } description: {
                Text(store.browserState.statusLine)
            } actions: {
                if case .failed = store.browserState {
                    Button("重试") {
                        Task { await store.reloadBrowser() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
