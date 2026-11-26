import SwiftUI
import OneDayCore

/// MCP 面（棒 4，对位 #50）：服务器清单（启停/测
/// 试）＋可安装目录；插件预置条目服务端不许端侧改
/// 开关（网页端实测 409 口径），开关置灰并明示
struct MacHubMCPView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "MCP 服务器", count: store.mcpServers.count
            )
            if store.mcpServers.isEmpty {
                HubEmptyText(text: "暂无 MCP 服务器。")
            }
            ForEach(store.mcpServers) { server in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .font(.callout.weight(.medium))
                        Text([
                            server.originLabel,
                            server.endpointLine,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("测试") {
                        Task {
                            await store.testMCP(
                                session: session, name: server.name
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    Toggle("", isOn: Binding(
                        get: { server.enabled },
                        set: { newValue in
                            Task {
                                await store.setMCPEnabled(
                                    session: session,
                                    name: server.name,
                                    enabled: newValue
                                )
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(server.isPluginProvided)
                }
                Divider()
            }
            if store.mcpServers.contains(where: \.isPluginProvided) {
                Text("插件预置的服务器开关在服务端锁定，本面只呈现状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !store.mcpCatalog.isEmpty {
                HubSectionHeader(
                    title: "可安装目录", count: store.mcpCatalog.count
                )
                ForEach(
                    Array(store.mcpCatalog.enumerated()), id: \.offset
                ) { _, entry in
                    let name = entry.hubFirstStr(["name", "id"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.callout.weight(.medium))
                            Text(entry.hubFirstStr(["description"])
                                ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("安装") {
                            Task { await install(entry) }
                        }
                        .buttonStyle(.borderless)
                    }
                    Divider()
                }
            }
        }
    }

    private func install(_ entry: JSONValue) async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        var body = entry.hubDict
        if body.isEmpty {
            body = ["name": entry]
        }
        do {
            try await session.chatClient.hubMCPInstall(
                config: config, apiKey: key, body: body
            )
            store.actionNote = "MCP 已安装（已回读清单）"
            await store.load(.mcp, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "安装 MCP 失败"
        }
    }
}
