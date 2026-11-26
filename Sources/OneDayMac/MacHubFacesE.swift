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

/// 模型与服务商面（棒 4，对位 #63）：可选模型清单
/// ＋设主模型＋辅助模型/MoA 配置呈现（/api/model
/// 系既有口，与 iOS 模型面同源）
struct MacHubModelsFaceView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmModel: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "可选模型", count: store.modelOptions.count
            )
            if store.modelOptions.isEmpty {
                HubEmptyText(text: "模型清单暂不可用。")
            }
            ForEach(store.modelOptions, id: \.self) { model in
                HStack(spacing: 8) {
                    Text(model)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button("设为主模型") { confirmModel = model }
                        .buttonStyle(.borderless)
                }
                Divider()
            }
            if let auxiliary = store.auxiliary {
                HubSectionHeader(title: "辅助模型")
                HubJSONSummaryView(value: auxiliary)
            }
            if let moa = store.moa {
                HubSectionHeader(title: "MoA 配置")
                HubJSONSummaryView(value: moa)
            }
        }
        .confirmationDialog(
            "把主模型设为所选模型？",
            isPresented: Binding(
                get: { confirmModel != nil },
                set: { if !$0 { confirmModel = nil } }
            )
        ) {
            Button("设置") {
                if let model = confirmModel {
                    Task {
                        await store.setMainModel(
                            session: session, model: model
                        )
                    }
                }
                confirmModel = nil
            }
            Button("取消", role: .cancel) { confirmModel = nil }
        }
    }
}

/// 配对管理面（棒 4，对位 #62）：待批配对（批准/
/// 清空）＋已配对（撤销），走面板 /api/pairing 系
/// （cookie 随共享会话自动带上，与 iOS 同路），
/// 动作后回读清单对账
struct MacHubPairingView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmRevoke: (platform: String, userID: String)?
    @State private var confirmClear = false

    private var pending: [JSONValue] {
        store.pairing?.hubFirstList(
            ["pending", "pending_requests"]
        ) ?? []
    }

    private var paired: [JSONValue] {
        store.pairing?.hubFirstList(
            ["paired", "approved", "users"]
        ) ?? []
    }

    var body: some View {
        HubScroll {
            HStack(spacing: 8) {
                HubSectionHeader(
                    title: "待批配对", count: pending.count
                )
                Spacer()
                if !pending.isEmpty {
                    Button("清空待批") { confirmClear = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
            }
            if pending.isEmpty {
                HubEmptyText(text: "暂无待批配对。")
            }
            ForEach(Array(pending.enumerated()), id: \.offset) { _, row in
                let platform = row.hubFirstStr(
                    ["platform", "channel"]
                ) ?? ""
                let requestID = row.hubFirstStr(
                    ["request_id", "id"]
                ) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.hubFirstStr(
                            ["user_name", "name", "user_id"]
                        ) ?? requestID)
                            .font(.callout.weight(.medium))
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("批准") {
                        Task {
                            await store.pairingApprove(
                                session: session,
                                platform: platform,
                                requestID: requestID
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            HubSectionHeader(title: "已配对", count: paired.count)
            if paired.isEmpty {
                HubEmptyText(text: "暂无已配对用户。")
            }
            ForEach(Array(paired.enumerated()), id: \.offset) { _, row in
                let platform = row.hubFirstStr(
                    ["platform", "channel"]
                ) ?? ""
                let userID = row.hubFirstStr(
                    ["user_id", "id"]
                ) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.hubFirstStr(
                            ["user_name", "name"]
                        ) ?? userID)
                            .font(.callout.weight(.medium))
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("撤销") {
                        confirmRevoke = (platform, userID)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Divider()
            }
        }
        .confirmationDialog(
            "撤销这条配对？",
            isPresented: Binding(
                get: { confirmRevoke != nil },
                set: { if !$0 { confirmRevoke = nil } }
            )
        ) {
            Button("撤销", role: .destructive) {
                if let target = confirmRevoke {
                    Task {
                        await store.pairingRevoke(
                            session: session,
                            platform: target.platform,
                            userID: target.userID
                        )
                    }
                }
                confirmRevoke = nil
            }
            Button("取消", role: .cancel) { confirmRevoke = nil }
        }
        .confirmationDialog(
            "清空全部待批配对？",
            isPresented: $confirmClear
        ) {
            Button("清空", role: .destructive) {
                Task {
                    await store.pairingClearPending(session: session)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

/// 用量面（棒 4，对位 #64）：近 30 天总量＋按日明
/// 细＋按模型明细（/api/analytics 系，与 iOS 用量
/// 面同口径：Token＝输入＋输出，缓存读不并入）
struct MacHubUsageView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            if let usage = store.usage {
                HubSectionHeader(title: "近 30 天总量")
                HubKVView(
                    label: "Token（入＋出）",
                    value: Self.formatTokens(usage.totals.tokens)
                )
                HubKVView(
                    label: "会话数",
                    value: "\(usage.totals.totalSessions ?? 0)"
                )
                HubKVView(
                    label: "API 调用",
                    value: "\(usage.totals.totalAPICalls ?? 0)"
                )
                if let cost = usage.totals.totalEstimatedCost {
                    HubKVView(
                        label: "估算费用",
                        value: String(format: "$%.2f", cost)
                    )
                }
                HubSectionHeader(
                    title: "按日", count: usage.daily.count
                )
                ForEach(usage.daily) { day in
                    HStack(spacing: 8) {
                        Text(day.day)
                            .font(.callout)
                            .frame(width: 90, alignment: .leading)
                        Text(Self.formatTokens(day.tokens))
                            .font(.callout)
                        Spacer()
                        Text("\(day.sessions ?? 0) 会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "用量数据暂不可用。")
            }
            if let models = store.modelUsage {
                HubSectionHeader(
                    title: "按模型", count: models.models.count
                )
                ForEach(models.models) { model in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model)
                                .font(.callout.weight(.medium))
                            Text(model.provider ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.formatTokens(model.tokens))
                            .font(.callout)
                    }
                    Divider()
                }
            }
        }
    }

    static func formatTokens(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(Int(value))"
    }
}
