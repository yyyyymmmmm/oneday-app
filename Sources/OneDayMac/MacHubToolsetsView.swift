import SwiftUI
import OneDayCore

/// 工具集面（棒 4，对位 #47）：/v1/toolsets 平台真
/// 值清单＋启停开关（回读为准）
struct MacHubToolsetsView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "工具集", count: store.toolsetRows.count
            )
            if store.toolsetRows.isEmpty {
                HubEmptyText(text: "工具集清单暂不可用。")
            }
            ForEach(
                Array(store.toolsetRows.enumerated()), id: \.offset
            ) { _, row in
                let name = row.hubFirstStr(["name", "id"]) ?? ""
                let enabled = row.hubBool("enabled") ?? false
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.callout.weight(.medium))
                        Text(row.hubFirstStr(
                            ["description", "platform"]
                        ) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            Task {
                                await store.setToolset(
                                    session: session, name: name,
                                    enabled: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
                Divider()
            }
        }
    }
}
