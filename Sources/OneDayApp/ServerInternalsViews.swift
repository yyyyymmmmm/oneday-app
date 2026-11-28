import OneDayCore
import OneDayDesign
import SwiftUI

/// H13 小件的操作组装（DESIGN §390）：三处呈现（技能页
/// 策展块、状态页会话统计块、自动化面钩子页）共用一份
/// ServerInternalsOperations 拼装
extension ServerInternalsOperations {
    static func live(appState: AppState) -> ServerInternalsOperations {
        ServerInternalsOperations(
            curatorStatus: {
                try await appState.performAdmin { client, config in
                    try await client.curatorStatus(config: config)
                }
            },
            setCuratorPaused: { paused in
                try await appState.performAdmin { client, config in
                    try await client.setCuratorPaused(config: config, paused: paused)
                }
            },
            activeProfileName: {
                try await appState.performAdmin { client, config in
                    try await client.activeProfileName(config: config)
                }
            },
            runCurator: { profile in
                try await appState.performAdmin { client, config in
                    try await client.runCurator(config: config, profile: profile)
                }
            },
            sessionStats: {
                try await appState.performAdmin { client, config in
                    try await client.sessionStoreStats(config: config)
                }
            },
            opsHooks: {
                try await appState.performAdmin { client, config in
                    try await client.opsHooks(config: config)
                }
            }
        )
    }
}

/// 段头＋组卡的统一外形（与宿主页 SectionLabel＋odGroup
/// 同方言）：标题、组卡、脚注说明
private struct InternalsBlock<Content: View>: View {
    let title: String
    let footer: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .odGroup()
            Text(footer)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
                .padding(.horizontal, OneDayMetrics.spacingM)
        }
    }
}

/// 技能整理块（H13 curator 自动半边，DESIGN §390；技能页
/// 尾部）：服务端策展器周期性复盘技能库（合并重复、归档
/// 陈旧）。看状态、暂停/恢复、立即跑一次；跑一次只算受
/// 理，跑完看「上次整理」时间更新
struct CuratorBlock: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServerInternalsStore()

    private var ops: ServerInternalsOperations { .live(appState: appState) }

    var body: some View {
        InternalsBlock(
            title: "技能整理",
            footer: "Hermes 会定期复盘技能库：合并重复的、归档很久没用的。整理只动技能，不动对话和记忆。"
        ) {
            if let note = store.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(
                        store.noteIsProblem
                            ? Palette.danger : Palette.inkSecondary
                    )
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            if store.curatorNotLoggedIn {
                Text("登录已失效，重新连接服务器后这里会显示技能整理状态。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(OneDayMetrics.spacingM)
            } else if let curator = store.curator {
                curatorRows(curator)
            } else if store.curatorFailed {
                Text("技能整理状态没读到，下拉刷新再试。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(OneDayMetrics.spacingM)
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取技能整理状态…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(OneDayMetrics.spacingM)
            }
        }
        .task { await store.loadCurator(ops: ops) }
    }

    @ViewBuilder
    private func curatorRows(_ curator: CuratorStatus) -> some View {
        KeyValueRow(
            "自动整理",
            value: curator.enabled
                ? (curator.paused ? "已暂停" : "开着") : "未开启"
        )
        if let last = curator.lastRunAt, !last.isEmpty {
            GroupDivider()
            KeyValueRow("上次整理", value: last)
        }
        if let hours = curator.intervalHours {
            GroupDivider()
            KeyValueRow("整理间隔", value: "每 \(hours.formatted()) 小时")
        }
        if curator.enabled {
            GroupDivider()
            HStack(spacing: OneDayMetrics.spacingM) {
                Button(curator.paused ? "恢复自动整理" : "暂停自动整理") {
                    Task {
                        await store.setCuratorPaused(
                            ops: ops, paused: !curator.paused
                        )
                    }
                }
                .disabled(store.curatorBusy)
                Button("现在整理一次") {
                    Task { await store.runCuratorNow(ops: ops) }
                }
                .disabled(store.curatorBusy || curator.paused)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
        }
    }
}

/// 会话存储统计块（H13 口径复核，DESIGN §390；状态页系
/// 统段）：读 /api/sessions/stats——会话库口径（总数含压
/// 缩链折行，与会话名单同口径）；与系统面
/// /api/system/stats 不是一回事，两处并存各表一面
struct SessionStatsBlock: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServerInternalsStore()

    private var ops: ServerInternalsOperations { .live(appState: appState) }

    var body: some View {
        InternalsBlock(
            title: "会话存储",
            footer: "按来源分的会话数与会话名单同口径（长对话压缩后折成一行计）。"
        ) {
            if let stats = store.stats {
                KeyValueRow("会话总数", value: "\(stats.total)")
                GroupDivider()
                KeyValueRow("消息总数", value: "\(stats.messages)")
                GroupDivider()
                KeyValueRow("已归档", value: "\(stats.archived)")
                ForEach(stats.bySource) { row in
                    GroupDivider()
                    KeyValueRow(row.source, value: "\(row.count)")
                }
            } else if store.statsFailed {
                Text("会话统计没读到，下拉刷新再试。")
                    .font(.callout)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(OneDayMetrics.spacingM)
            } else {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView()
                    Text("正在读取会话统计…")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(OneDayMetrics.spacingM)
            }
        }
        .task { await store.loadStats(ops: ops) }
    }
}

/// 运维钩子管理页（Wave 8 升级为完整增删闭环）：
/// 对接 `GET/POST/DELETE /api/ops/hooks`，支持查看已配事件钩子、
/// 新增命令钩子（自动写入同意白名单）与左滑删除撤销授权。
struct OpsHooksView: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServerInternalsStore()
    @State private var showAddSheet = false
    @State private var mutationError: String?

    private var ops: ServerInternalsOperations { .live(appState: appState) }

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "bolt.horizontal.circle.fill",
                tint: Palette.tintOrangeInk,
                title: "运维事件钩子",
                subtitle: "在会话开始、工具调用前后等事件点自动执行 Shell 命令，支持一键新增与左滑移除。",
                statusText: store.hooks.map { "\($0.hooks.count) 条钩子" },
                statusTone: .healthy
            )

            if let mutationError {
                Section {
                    Label(mutationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Palette.surface)
            }

            if let page = store.hooks {
                Section {
                    if page.hooks.isEmpty {
                        Text("服务器上还没有配置事件钩子，点击右上角 + 添加。")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    ForEach(page.hooks) { hook in
                        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                            HStack(spacing: OneDayMetrics.spacingS) {
                                Text(hook.event)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Palette.ink)
                                if !hook.allowed {
                                    SettingsStatusPill(text: "未获准", tone: .error)
                                } else if !hook.executable {
                                    SettingsStatusPill(text: "命令不在", tone: .warning)
                                }
                            }
                            if !hook.matcher.isEmpty {
                                Text("匹配：\(hook.matcher)")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                            Text(hook.command)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await deleteHook(hook) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    SettingsSectionHeader("已配的钩子（左滑删除）")
                }
                .listRowBackground(Palette.surface)

                if !page.validEvents.isEmpty {
                    Section {
                        Text(page.validEvents.joined(separator: "、"))
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    } header: {
                        SettingsSectionHeader("可用的事件点")
                    }
                    .listRowBackground(Palette.surface)
                }
            } else if store.hooksFailed {
                Section {
                    InlineError("钩子名单没读到，下拉刷新再试。")
                }
                .listRowBackground(Palette.surface)
            } else {
                Section {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取钩子…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("运维钩子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增钩子")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddOpsHookSheet(validEvents: store.hooks?.validEvents ?? []) {
                await store.loadHooks(ops: ops)
            }
        }
        .task { await store.loadHooks(ops: ops) }
        .refreshable { await store.loadHooks(ops: ops) }
    }

    private func deleteHook(_ hook: OpsHookItem) async {
        mutationError = nil
        do {
            try await appState.performAdmin { config in
                try await appState.client.deleteOpsHook(
                    config: config, event: hook.event, command: hook.command
                )
            }
            Haptics.success()
            await store.loadHooks(ops: ops)
        } catch {
            mutationError = error.localizedDescription
        }
    }
}

private struct AddOpsHookSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let validEvents: [String]
    let onSaved: () async -> Void

    @State private var event = "session_start"
    @State private var command = ""
    @State private var matcher = ""
    @State private var approve = true
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("钩子触发配置") {
                    TextField("事件名（如 session_start / pre_tool_call）", text: $event)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !validEvents.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(validEvents.prefix(8), id: \.self) { candidate in
                                    Button(candidate) {
                                        event = candidate
                                        Haptics.selection()
                                    }
                                    .font(.caption2.monospaced())
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    TextField("Shell 命令（如 echo ok）", text: $command)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("工具匹配器 Matcher（可选）", text: $matcher)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("同时写入服务端同意白名单（立即生效）", isOn: $approve)
                }

                if let errorText {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("新增运维钩子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(
                        event.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || saving
                    )
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            try await appState.performAdmin { config in
                try await appState.client.createOpsHook(
                    config: config,
                    event: event.trimmingCharacters(in: .whitespacesAndNewlines),
                    command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                    matcher: matcher.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : matcher.trimmingCharacters(in: .whitespacesAndNewlines),
                    approve: approve
                )
            }
            Haptics.success()
            await onSaved()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
