import SwiftUI
import OneDayCore

/// 枢纽中栏（棒 4，对位 #11）：管理面清单（24 面，
/// 序与拟案 1.4 枢纽行一致）；选中态由壳层持有，
/// 详情区按面渲染。21/22 号归聊天补全小棒不在此列。
struct MacHubView: View {
    @Binding var face: MacHubFace?

    var body: some View {
        List(selection: $face) {
            Section {
                ForEach(MacHubFace.allCases) { item in
                    Label {
                        HStack(spacing: 6) {
                            Text(item.title)
                            Spacer()
                            Text("#\(item.parityNumber)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                    .tag(item)
                }
            } header: {
                Text("管理面")
            } footer: {
                Text("全部走现行网关 API，零新后端；写动作以回读为终局。")
                    .font(.caption)
            }
        }
        .listStyle(.sidebar)
    }
}

/// 枢纽详情路由：统一面chrome（标题＋刷新＋错误/动
/// 作提示横幅＋加载态），面本体在 MacHubFaces* 文件。
struct MacHubDetailView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    let face: MacHubFace?

    var body: some View {
        Group {
            if let face {
                faceBody(face)
            } else {
                ContentUnavailableView(
                    "枢纽",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("从中间一栏选一个管理面。")
                )
            }
        }
    }

    @ViewBuilder
    private func faceBody(_ face: MacHubFace) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: face.systemImage)
                    .foregroundStyle(.secondary)
                Text(face.title)
                    .font(.headline)
                Text("对位 #\(face.parityNumber)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if store.isLoading(face) {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task {
                        await store.load(
                            face, session: session, force: true
                        )
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新（回读服务端真值）")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            if let error = store.errors[face] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            if let note = store.actionNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            faceContent(face)
        }
        .task(id: face) {
            await store.load(face, session: session)
        }
    }

    @ViewBuilder
    private func faceContent(_ face: MacHubFace) -> some View {
        switch face {
        case .ledger: MacHubLedgerView(store: store)
        case .audit: MacHubAuditView()
        case .computer: MacHubComputerView(store: store)
        case .identity: MacHubIdentityView(store: store)
        case .mail: MacHubMailView(store: store)
        case .profiles: MacHubProfilesView(store: store)
        case .memory: MacHubMemoryView(store: store)
        case .skills: MacHubSkillsView(store: store)
        case .toolsets: MacHubToolsetsView(store: store)
        case .delegation: MacHubDelegationView(store: store)
        case .cron: MacHubCronView(store: store)
        case .mcp: MacHubMCPView(store: store)
        case .connectors: MacHubConnectorsView(store: store)
        case .channels: MacHubChannelsView(store: store)
        case .devices: MacHubDevicesView(store: store)
        case .monitors: MacHubMonitorsView(store: store)
        case .webhooks: MacHubWebhooksView(store: store)
        case .presets: MacHubPresetsView(store: store)
        case .env: MacHubEnvView(store: store)
        case .kanban: MacHubKanbanView(store: store)
        case .gateway: MacHubGatewayView(store: store)
        case .models: MacHubModelsFaceView(store: store)
        case .pairing: MacHubPairingView(store: store)
        case .usage: MacHubUsageView(store: store)
        }
    }
}

/// 面内滚动容器（各面共用内边距口径）
struct HubScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

/// 面内分节标题
struct HubSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 键值行（状态类面共用）
struct HubKVView: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// JSONValue 宽容呈现：对象逐键成行（标量直印、数
/// 组只报件数、对象只报键数——深层内容由各面专属
/// 段呈现，这里只做状态总览，不冒充全文）
struct HubJSONSummaryView: View {
    let value: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(
                Array(value.hubDict.keys.sorted()), id: \.self
            ) { key in
                HubKVView(label: key, value: describe(value.hubDict[key]))
            }
            if value.hubDict.isEmpty {
                if !value.hubList.isEmpty {
                    Text("共 \(value.hubList.count) 项（见下方清单）")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let text = value.stringValue {
                    Text(text).font(.callout)
                } else {
                    Text("暂无数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func describe(_ item: JSONValue?) -> String {
        guard let item else { return "—" }
        switch item {
        case .string(let text): return text
        case .number, .bool: return item.displayString
        case .array(let values): return "\(values.count) 项"
        case .object(let dict): return "\(dict.count) 个字段"
        case .null: return "—"
        }
    }
}

/// 面内空态行
struct HubEmptyText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
