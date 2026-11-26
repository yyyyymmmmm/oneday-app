import SwiftUI
import OneDayCore

/// 频道面（棒 4，对位 #52）：消息平台全量＋网关频
/// 道两段状态呈现（配置在服务端/各平台侧，本面只
/// 读，与 iOS 频道面同口径）
struct MacHubChannelsView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "消息平台")
            if let platforms = store.platforms {
                let rows = platforms.hubFirstList(
                    ["platforms", "items"]
                )
                if rows.isEmpty {
                    HubJSONSummaryView(value: platforms)
                } else {
                    ForEach(
                        Array(rows.enumerated()), id: \.offset
                    ) { _, platform in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.hubFirstStr(
                                    ["name", "platform", "id"]
                                ) ?? "（未命名平台）")
                                    .font(.callout.weight(.medium))
                                Text(platform.hubFirstStr(
                                    ["status", "state"]
                                ) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let enabled = platform.hubBool(
                                "enabled"
                            ) {
                                Text(enabled ? "启用中" : "已停用")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }
                }
            } else {
                HubEmptyText(text: "消息平台暂不可用。")
            }
            HubSectionHeader(title: "网关频道")
            if let channels = store.channels {
                HubJSONSummaryView(value: channels)
            } else {
                HubEmptyText(text: "网关频道暂不可用。")
            }
        }
    }
}
