import SwiftUI
import OneDayCore

/// 网关状态面（棒 4，对位 #59/#60）：服务端状态
/// （版本/网关运行态/平台连接）＋网关启停重启动作
/// （动作后回读状态对账）；服务器会话清单在设备面
struct MacHubGatewayView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmAction: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "服务端状态")
            if let status = store.serverStatus {
                HubKVView(
                    label: "Hermes 版本",
                    value: status.version ?? "未知"
                )
                HubKVView(
                    label: "网关",
                    value: status.gatewayRunning == true
                        ? "运行中"
                        : (status.gatewayState ?? "未运行")
                )
                if let overall = status.overall {
                    HubKVView(label: "总评", value: overall)
                }
                HubSectionHeader(
                    title: "平台连接",
                    count: status.platforms.count
                )
                ForEach(
                    status.platforms.keys.sorted(), id: \.self
                ) { platform in
                    HubKVView(
                        label: platform,
                        value: status.platforms[platform]?.state
                            ?? ""
                    )
                }
            } else {
                HubEmptyText(text: "服务端状态暂不可用。")
            }
            HubSectionHeader(title: "网关动作")
            HStack(spacing: 10) {
                Button("启动") { confirmAction = "start" }
                Button("重启") { confirmAction = "restart" }
                Button("停止") { confirmAction = "stop" }
                    .foregroundStyle(.red)
            }
            Text("停止/重启会短暂中断所有会话的实时推送，动作后本面自动回读状态对账。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "确认执行网关动作？",
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            )
        ) {
            Button(
                confirmAction == "stop" ? "停止" : "执行",
                role: confirmAction == "stop"
                    ? .destructive : .none
            ) {
                if let action = confirmAction {
                    Task {
                        await store.gatewayAction(
                            session: session, action: action
                        )
                    }
                }
                confirmAction = nil
            }
            Button("取消", role: .cancel) { confirmAction = nil }
        }
    }
}
