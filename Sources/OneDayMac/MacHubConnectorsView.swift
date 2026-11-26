import SwiftUI
import OneDayCore

/// 连接器面（棒 4，对位 #51）：目录走 Core 静态目
/// 录单源（八家＋接入说明如实标注）；已连接＝端点
/// 读到的 MCP 服务器（Core ConnectedConnector 同
/// 口径：端点读到的才算已连接）
struct MacHubConnectorsView: View {
    let store: MacHubStore

    private var catalog: [ConnectorCatalogEntry] {
        ConnectorDirectory.catalog
    }

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "已连接（服务端在册）",
                count: store.mcpServers.count
            )
            if store.mcpServers.isEmpty {
                HubEmptyText(text: "服务端暂无在册连接。")
            }
            ForEach(store.mcpServers) { server in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ConnectedConnector(server: server)
                            .displayName)
                            .font(.callout.weight(.medium))
                        Text(server.originLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(server.enabled ? "启用中" : "已停用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
            }
            HubSectionHeader(title: "可连接目录", count: catalog.count)
            ForEach(catalog) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(entry.name)
                            .font(.callout.weight(.medium))
                        Text(entry.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(entry.blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(entry.accessDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                Divider()
            }
        }
    }
}
