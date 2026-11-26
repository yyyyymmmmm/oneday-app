import SwiftUI
import OneDayCore
import OneDayDesign

/// 诊断与日志页（棒 5 / mac-07，对位 #82/#83/#84/#85/#86）：
/// - 连接自检（#82）：复用 Core SelfCheckReportBuilder 单源并发只读探活
/// - 运维体检与存档（#83）：doctor / security-audit / backup + checkpoints
/// - 系统日志（#84）：/api/logs 级别筛选＋搜索＋复制
/// - 聊天与能力诊断（#85）：主题色值解析、能力协商表、包版本、脱敏摘要复制
/// - 设置注册表（#86）：features.settings_registry 亮时只读展示
struct MacSettingsDiagnosticsPane: View {
    @Environment(SessionStore.self) private var session

    private enum SubTab: String, CaseIterable, Identifiable {
        case selfCheck = "连接自检"
        case ops = "体检与存档"
        case logs = "系统日志"
        case chat = "聊天与能力"
        var id: String { rawValue }
    }

    @State private var tab: SubTab = .selfCheck

    // 连接自检（#82）
    @State private var report: SelfCheckReport?
    @State private var checking = false

    // 运维体检（#83）
    @State private var opsOutput = ""
    @State private var opsRunning = false
    @State private var checkpoints: [CheckpointsResponse.Session] = []

    // 系统日志（#84）
    @State private var logLevel = ""
    @State private var logSearch = ""
    @State private var logLines: [String] = []
    @State private var logsLoading = false
    @State private var logsError: String?

    // 设置注册表（#86）
    @State private var registry: SettingsRegistryResponse?

    var body: some View {
        VStack(spacing: 0) {
            Picker("诊断面板", selection: $tab) {
                ForEach(SubTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            switch tab {
            case .selfCheck:
                selfCheckView
            case .ops:
                opsView
            case .logs:
                logsView
            case .chat:
                chatDiagnosticsView
            }
        }
        .task {
            if report == nil && session.isConnected {
                await runSelfCheck()
            }
            await loadRegistryIfSupported()
        }
    }

    // MARK: - 连接自检（#82，Core SelfCheckReportBuilder 单源）

    private var selfCheckView: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report?.overallWord ?? (checking ? "正在自检…" : "尚未自检"))
                            .font(.headline)
                        if let report {
                            Text("上次自检：\(report.checkedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Spacer()
                    Button(checking ? "自检中…" : "重新自检") {
                        Task { await runSelfCheck() }
                    }
                    .disabled(checking || !session.isConnected)
                }
            }

            if let report {
                ForEach(report.groups) { group in
                    Section(group.title) {
                        ForEach(group.rows) { row in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(dotColor(for: row.status))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(row.title)
                                            .font(.system(size: 13))
                                        Spacer()
                                        if let value = row.value {
                                            Text(value)
                                                .font(.caption)
                                                .foregroundStyle(Palette.inkSecondary)
                                        }
                                    }
                                    Text(row.reason.map { "\(row.status.word) · \($0)" } ?? row.status.word)
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                            }
                        }
                    }
                }
            } else if !session.isConnected {
                Section {
                    Text("连接服务器后可运行只读探活自检。")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 运维体检与存档（#83）

    private var opsView: some View {
        Form {
            Section("一键运维动作") {
                HStack(spacing: 10) {
                    Button("运行 Doctor 体检") {
                        Task { await runOps(action: "doctor") }
                    }
                    .disabled(opsRunning || !session.isConnected)
                    Button("运行安全审计") {
                        Task { await runOps(action: "security-audit") }
                    }
                    .disabled(opsRunning || !session.isConnected)
                    Button("创建服务端备份") {
                        Task { await runOps(action: "backup") }
                    }
                    .disabled(opsRunning || !session.isConnected)
                }
                if opsRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("服务端执行中，正在回读日志…")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if !opsOutput.isEmpty {
                    ScrollView {
                        Text(opsOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                }
            }

            Section("检查点存档") {
                if checkpoints.isEmpty {
                    Text("暂无服务端检查点记录")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    ForEach(checkpoints, id: \.session) { item in
                        LabeledContent(
                            item.session,
                            value: "\(item.files) 个文件 · \(item.bytes) B"
                        )
                    }
                }
                Button("刷新检查点") {
                    Task { await loadCheckpoints() }
                }
                .disabled(!session.isConnected)
            }
        }
        .formStyle(.grouped)
        .task { await loadCheckpoints() }
    }

    // MARK: - 系统日志（#84）

    private var logsView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("级别", selection: $logLevel) {
                    Text("全部").tag("")
                    Text("INFO").tag("INFO")
                    Text("WARNING").tag("WARNING")
                    Text("ERROR").tag("ERROR")
                }
                .labelsHidden()
                .frame(width: 100)

                TextField("搜索日志关键词", text: $logSearch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await loadLogs() } }

                Button("查询") { Task { await loadLogs() } }
                    .disabled(logsLoading || !session.isConnected)

                Button("复制") {
                    Pasteboard.copy(logLines.joined(separator: "\n"))
                }
                .disabled(logLines.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let logsError {
                Text(logsError)
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                    .padding(.horizontal, 16)
            }

            ScrollView {
                if logLines.isEmpty {
                    Text(logsLoading ? "正在加载日志…" : "暂无日志行")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .bottom], 14)
        }
        .task {
            if logLines.isEmpty && session.isConnected {
                await loadLogs()
            }
        }
    }

    // MARK: - 聊天与能力诊断（#85/#86）

    private var chatDiagnosticsView: some View {
        let theme = Palette.currentChatTheme
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVer = info["CFBundleShortVersionString"] as? String ?? "—"
        let buildVer = info["CFBundleVersion"] as? String ?? "—"
        let bundleID = Bundle.main.bundleIdentifier ?? "site.didichou.oneday.mac"

        return Form {
            Section("客户端本体信息") {
                LabeledContent("Bundle ID", value: bundleID)
                LabeledContent("版本号", value: "v\(shortVer) (\(buildVer))")
                LabeledContent("当前主题", value: theme.displayName)
                LabeledContent(
                    "用户泡色值（浅 / 暗）",
                    value: String(
                        format: "#%06X / #%06X",
                        theme.bubbleFill(dark: false),
                        theme.bubbleFill(dark: true)
                    )
                )
            }

            Section("能力协商单源状态") {
                LabeledContent(
                    "选择框 (options_card)",
                    value: availabilityWord(
                        CapabilityNegotiation.optionsCardAvailability(session.capabilities)
                    )
                )
                LabeledContent(
                    "AI 自反应 (self_reactions)",
                    value: availabilityWord(
                        CapabilityNegotiation.selfReactionsAvailability(session.capabilities)
                    )
                )
                LabeledContent(
                    "任务幂等 (runs_idempotency)",
                    value: availabilityWord(
                        CapabilityNegotiation.runIdempotencyAvailability(session.capabilities)
                    )
                )
                LabeledContent(
                    "消息级幂等 (client_message_id)",
                    value: availabilityWord(
                        CapabilityNegotiation.clientMessageIdAvailability(session.capabilities)
                    )
                )
                LabeledContent(
                    "设置注册表 (settings_registry)",
                    value: availabilityWord(
                        CapabilityNegotiation.settingsRegistryAvailability(session.capabilities)
                    )
                )
            }

            if let registry, !registry.records.isEmpty {
                Section("服务端设置注册表（只读）") {
                    ForEach(registry.records) { rec in
                        LabeledContent(
                            rec.title.isEmpty ? rec.key : rec.title,
                            value: Self.displayValue(rec.effectiveValue)
                        )
                    }
                }
            }

            Section {
                Button("复制脱敏诊断摘要") {
                    let summary = """
                    OneDayMac v\(shortVer) (\(buildVer)) [\(bundleID)]
                    Server: \(session.config?.host ?? "未连接") | Hermes: \(session.hermesVersion ?? "—")
                    Theme: \(theme.displayName) | Models: \(session.modelCount)
                    SelfCheck: \(report?.overallWord ?? "未运行")
                    """
                    Pasteboard.copy(summary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 执行逻辑

    private func runSelfCheck() async {
        guard let config = session.config else { return }
        let apiKey = session.apiKey
        let client = session.chatClient
        checking = true
        defer { checking = false }

        async let healthFetch = Self.wrapFetch { try await client.health(config: config) }
        async let statusFetch = Self.wrapFetch { try await client.status(config: config) }

        let capsFetch: SelfCheckFetch<CapabilitiesResponse>
        let detFetch: SelfCheckFetch<HealthDetailedResponse>
        let appFetch: SelfCheckFetch<ApprovalsListResponse>
        let grantsFetch: SelfCheckFetch<GrantsListResponse>
        if let apiKey {
            async let c = Self.wrapFetch { try await client.capabilities(config: config, apiKey: apiKey) }
            async let d = Self.wrapFetch { try await client.healthDetailed(config: config, apiKey: apiKey) }
            async let a = Self.wrapFetch { try await client.listApprovalsSummary(config: config, apiKey: apiKey) }
            async let g = Self.wrapFetch { try await client.grants(config: config, apiKey: apiKey) }
            capsFetch = await c
            detFetch = await d
            appFetch = await a
            grantsFetch = await g
        } else {
            capsFetch = .failure(.missingCredentials)
            detFetch = .failure(.missingCredentials)
            appFetch = .failure(.missingCredentials)
            grantsFetch = .failure(.missingCredentials)
        }

        let enrollProbe = await client.routeProbe(
            config: config, apiKey: apiKey, path: "/v1/enrollment/claim"
        )
        let enrollFetch: SelfCheckFetch<RouteProbeResult> =
            enrollProbe.map { .success($0) } ?? .failure(.unreachable)

        var reactionsFetch: SelfCheckFetch<RouteProbeResult>?
        if let apiKey,
           let page = try? await client.sessionsPage(
               config: config, apiKey: apiKey, limit: 1, offset: 0, archived: nil
           ),
           let first = page.sessions.first {
            let probe = await client.routeProbe(
                config: config, apiKey: apiKey, path: "/v1/reactions/\(first.id)/1"
            )
            reactionsFetch = probe.map { .success($0) } ?? .failure(.unreachable)
        }

        report = SelfCheckReportBuilder.build(
            health: await healthFetch,
            capabilities: capsFetch,
            detailed: detFetch,
            status: await statusFetch,
            approvals: appFetch,
            grants: grantsFetch,
            enrollmentProbe: enrollFetch,
            reactionsProbe: reactionsFetch,
            checkedAt: Date()
        )
    }

    private func runOps(action: String) async {
        guard let config = session.config, let key = session.apiKey else { return }
        opsRunning = true
        opsOutput = ""
        defer { opsRunning = false }
        do {
            let spawn = try await session.chatClient.opsTrigger(
                config: config, apiKey: key, action: action
            )
            let name = spawn.name.isEmpty ? action : spawn.name
            for _ in 0..<15 {
                try? await Task.sleep(for: .seconds(1))
                let status = try await session.chatClient.opsActionStatus(
                    config: config, apiKey: key, name: name
                )
                opsOutput = status.lines.joined(separator: "\n")
                if status.running == false { break }
            }
            if action == "backup" { await loadCheckpoints() }
        } catch let error as HermesError {
            opsOutput = "执行失败：\(error.userMessage)"
        } catch {
            opsOutput = "执行失败：\(error.localizedDescription)"
        }
    }

    private func loadCheckpoints() async {
        guard let config = session.config, let key = session.apiKey else { return }
        if let res = try? await session.chatClient.opsCheckpoints(
            config: config, apiKey: key
        ) {
            checkpoints = res.sessions
        }
    }

    private static func displayValue(_ value: SettingsRegistryValue?) -> String {
        switch value {
        case .bool(let b): return b ? "开启" : "关闭"
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .string(let s): return s
        case nil: return "—"
        }
    }

    private func loadLogs() async {
        guard let config = session.config, let key = session.apiKey else { return }
        logsLoading = true
        logsError = nil
        defer { logsLoading = false }
        do {
            let res = try await session.chatClient.logs(
                config: config, apiKey: key,
                level: logLevel.isEmpty ? nil : logLevel,
                search: logSearch.isEmpty ? nil : logSearch,
                lines: 200
            )
            logLines = res.lines
        } catch let error as HermesError {
            logsError = error.userMessage
        } catch {
            logsError = error.localizedDescription
        }
    }

    private func loadRegistryIfSupported() async {
        guard let config = session.config, let key = session.apiKey,
              CapabilityNegotiation.settingsRegistryAvailability(
                  session.capabilities
              ) == .available
        else { return }
        registry = try? await session.chatClient.settingsRegistry(
            config: config, apiKey: key
        )
    }

    private nonisolated static func wrapFetch<T>(
        _ body: () async throws -> T
    ) async -> SelfCheckFetch<T> {
        do {
            return .success(try await body())
        } catch let error as HermesError {
            switch error {
            case .apiKeyRejected, .loginRejected: return .failure(.unauthorized)
            case .healthCheckFailed(let s), .unexpectedStatus(_, let s), .loginFailed(let s):
                return .failure(.httpStatus(s))
            case .serverError(_, _, let code): return .failure(.serverCode(code))
            case .decodingFailed: return .failure(.decoding)
            default: return .failure(.unreachable)
            }
        } catch {
            return .failure(.unreachable)
        }
    }

    private func dotColor(for status: SelfCheckRowStatus) -> Color {
        switch status {
        case .ok: return Palette.success
        case .warn: return Palette.warning
        case .off: return Palette.inkSecondary.opacity(0.55)
        case .unprobed: return Palette.inkSecondary.opacity(0.3)
        }
    }

    private func availabilityWord(_ a: CapabilityAvailability) -> String {
        switch a {
        case .available: return "已支持"
        case .unavailable: return "服务端未开放"
        case .unknown: return "未探测"
        }
    }
}
