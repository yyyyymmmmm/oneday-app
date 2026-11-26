import SwiftUI
import OneDayCore

/// 设备与主会话面（棒 4，对位 #53/#61，兼 #60 服
/// 务器会话）：设备会话/同步/主会话停泊态/登录会
/// 话四段状态呈现，全走 device-bridge 与 /v1/auth
/// 既有口（与 iOS MainSessionView 同源）
struct MacHubDevicesView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "主会话（停泊态）")
            if let park = store.parkState {
                HubJSONSummaryView(value: park)
            } else {
                HubEmptyText(text: "主会话状态暂不可用。")
            }
            HubSectionHeader(title: "设备会话")
            if let device = store.deviceSession {
                HubJSONSummaryView(value: device)
            } else {
                HubEmptyText(text: "设备会话暂不可用。")
            }
            HubSectionHeader(title: "同步状态")
            if let sync = store.deviceSync {
                HubJSONSummaryView(value: sync)
            } else {
                HubEmptyText(text: "同步状态暂不可用。")
            }
            HubSectionHeader(title: "登录会话")
            if let sessions = store.authSessions {
                let rows = sessions.hubFirstList(
                    ["sessions", "items"]
                )
                if rows.isEmpty {
                    HubJSONSummaryView(value: sessions)
                } else {
                    ForEach(
                        Array(rows.enumerated()), id: \.offset
                    ) { _, row in
                        HubKVView(
                            label: row.hubFirstStr(
                                ["client", "name", "id"]
                            ) ?? "会话",
                            value: row.hubFirstStr(
                                ["created_at", "last_seen", "status"]
                            ) ?? ""
                        )
                    }
                }
            } else {
                HubEmptyText(text: "登录会话暂不可用。")
            }
        }
    }
}
