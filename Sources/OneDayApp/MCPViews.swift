import OneDayCore
import OneDayDesign
import SwiftUI

/// MCP 连接页（P10，设置·智能体组）：服务端 MCP 服务器
/// 列表——来源（插件预置/手动配置）、连接地址、启停与
/// 连接测试。数据源＝GET /api/mcp/servers，2026-11-09
/// 只读联调拿过生产实样：{"servers":[…]}，在册的 box
/// 是插件预置（source=plugin），来源如实上屏不臆造。
/// 开关走 PUT …/enabled（与技能开关同族的同步配置写，
/// 沿技能页先例：乐观更新＋失败回滚）；测试走
/// POST …/test，回执无显式成功信号不判成功
/// （MCPTestResult 口径）。
/// 本页不提供新增/删除：OpenAPI 的 POST/DELETE 形状
/// 含完整服务器配置（命令/环境变量），凭据类字段不该
/// 在手机上裸录，配置面留电脑端。
struct MCPView: View {
    @Environment(AppState.self) private var appState

    @State private var servers: [MCPServerItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var notice: String?
    @State private var toggling: Set<String> = []
    @State private var testing: Set<String> = []
    @State private var testResults: [String: MCPTestResult] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !servers.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("共 \(servers.count) 个 · 启用 \(servers.filter { $0.enabled }.count) 个")
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .odGroup()
                    VStack(spacing: 0) {
                        ForEach(
                            Array(servers.enumerated()), id: \.element.id
                        ) { index, server in
                            if index > 0 {
                                GroupDivider(inset: OneDayMetrics.spacingM)
                            }
                            serverRow(server)
                        }
                    }
                    .odGroup()
                    .padding(.top, OneDayMetrics.spacingM)
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else if isLoading {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取 MCP 连接…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                } else {
                    EmptyState(
                        icon: "cable.connector",
                        title: "还没有 MCP 连接",
                        message: "服务端尚未配置任何 MCP 服务器。在电脑上给 Hermes 配置后会显示在这里。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("MCP 连接")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func serverRow(_ server: MCPServerItem) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: OneDayMetrics.spacingXS) {
                        Text(server.name)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text(server.originLabel)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.primaryTint, in: Capsule())
                    }
                    if let endpoint = server.endpointLine {
                        Text(endpoint)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Text(metaLine(server))
                        .font(.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Toggle("", isOn: toggleBinding(for: server))
                    .labelsHidden()
                    .disabled(toggling.contains(server.name))
            }
            HStack(spacing: OneDayMetrics.spacingSM) {
                Button("测试连接") {
                    Task { await test(server) }
                }
                .buttonStyle(.odSecondary)
                .disabled(testing.contains(server.name))
                if testing.contains(server.name) {
                    ProgressView()
                } else if let result = testResults[server.name] {
                    HStack(spacing: 4) {
                        Image(
                            systemName: result.succeeded
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(
                            result.succeeded ? Palette.success : Palette.danger
                        )
                        .accessibilityHidden(true)
                        Text(resultLine(result))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func metaLine(_ server: MCPServerItem) -> String {
        switch server.transport?.lowercased() {
        case "http", "streamable-http", "sse":
            return "远程连接"
        case "stdio":
            return "本地进程"
        case let other?:
            return other
        default:
            return "—"
        }
    }

    private func resultLine(_ result: MCPTestResult) -> String {
        var text = result.displayMessage
            ?? (result.succeeded ? "连接成功" : "连接未成功")
        if let count = result.toolCount {
            text += " · \(count) 个工具"
        }
        return text
    }

    private func toggleBinding(for server: MCPServerItem) -> Binding<Bool> {
        Binding(
            get: { server.enabled },
            set: { newValue in
                Task { await setEnabled(server, to: newValue) }
            }
        )
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            servers = try await appState.performAdmin { client, config in
                try await client.mcpServers(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage
                ?? "MCP 连接读取失败。"
        }
    }

    /// 开关：乐观更新，PUT 失败回滚＋提示（技能开关先例）
    private func setEnabled(_ server: MCPServerItem, to newValue: Bool) async {
        guard let index = servers.firstIndex(where: { $0.id == server.id })
        else { return }
        let original = servers[index]
        servers[index] = MCPServerItem(
            name: original.name, transport: original.transport,
            url: original.url, command: original.command,
            enabled: newValue,
            source: original.source, plugin: original.plugin
        )
        toggling.insert(server.name)
        defer { toggling.remove(server.name) }
        do {
            try await appState.performAdmin { client, config in
                try await client.setMCPServerEnabled(
                    config: config, name: server.name, enabled: newValue
                )
            }
            // 开关变了，旧测试结论作废
            testResults.removeValue(forKey: server.name)
        } catch {
            if let current = servers.firstIndex(where: { $0.id == server.id }) {
                servers[current] = original
            }
            notice = (error as? HermesError)?.userMessage ?? "开关切换失败。"
        }
    }

    private func test(_ server: MCPServerItem) async {
        testing.insert(server.name)
        defer { testing.remove(server.name) }
        do {
            testResults[server.name] = try await appState.performAdmin {
                client, config in
                try await client.testMCPServer(
                    config: config, name: server.name
                )
            }
        } catch {
            testResults[server.name] = MCPTestResult(
                ok: false, status: nil,
                message: (error as? HermesError)?.userMessage
                    ?? "测试请求失败",
                toolCount: nil
            )
        }
    }
}
