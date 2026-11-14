import OneDayDesign
import OneDayCore
import SwiftUI

/// 定时任务页（智能体格，IA v3 §5.2）：任务列表＋新建，
/// 点入详情做暂停/恢复/立即触发/编辑/删除与运行记录。
/// 接口口径：POST /api/cron/jobs（schedule 传字符串）、
/// PUT …/{id} {"updates": {…}}、POST …/pause|resume|trigger、
/// GET …/runs（运行记录与会话同构）。
struct CronJobsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    @State private var jobs: [CronJob] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showCreate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !jobs.isEmpty {
                    // 0.3.7 卡 15：摘要卡＋按状态两组
                    summaryCard
                    jobGroup(title: "开着的", jobs: jobs.filter(\.enabled))
                    jobGroup(title: "停着的", jobs: jobs.filter { !$0.enabled })
                } else if let errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else if isLoading {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取任务…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                } else {
                    ContentUnavailableView(
                        "还没有定时任务",
                        systemImage: "clock.arrow.2.circlepath",
                        description: Text("点右上角新建，让 Hermes 按计划自动干活。")
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("定时任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建定时任务")
            }
        }
        .sheet(isPresented: $showCreate) {
            CronJobFormView(job: nil) {
                Task { await load() }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onAppear {
            // 总览快捷动作深链：消费「新建」请求
            if appState.cronCreateRequested {
                appState.cronCreateRequested = false
                showCreate = true
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Text(summaryText)
                .font(.callout)
                .foregroundStyle(Palette.ink)
            Spacer()
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .odGroup()
    }

    private var summaryText: String {
        let enabled = jobs.filter(\.enabled)
        var text = "启用 \(enabled.count) 个"
        if let next = enabled.compactMap({ AdminFormat.iso($0.nextRunAt) }).min() {
            let calendar = Calendar.current
            let time = AdminFormat.timeOnly(next)
            if calendar.isDateInToday(next) {
                text += " · 下次运行 今天 \(time)"
            } else if calendar.isDateInTomorrow(next) {
                text += " · 下次运行 明天 \(time)"
            } else {
                text += " · 下次运行 \(AdminFormat.short(next))"
            }
        }
        return text
    }

    @ViewBuilder
    private func jobGroup(title: String, jobs groupJobs: [CronJob]) -> some View {
        if !groupJobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title)
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(Array(groupJobs.enumerated()), id: \.element.id) { index, job in
                        if index > 0 {
                            GroupDivider()
                        }
                        jobRow(job)
                    }
                }
                .odGroup()
            }
        }
    }

    private func jobRow(_ job: CronJob) -> some View {
        NavigationLink {
            CronJobDetailView(job: job) {
                Task { await load() }
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                StatusDot(color: job.enabled ? Palette.success : Palette.inkMuted)
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(job.title)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(job.scheduleText)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                    if job.enabled, let next = AdminFormat.iso(job.nextRunAt) {
                        Text("下次 \(AdminFormat.short(next))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                if job.lastError != nil {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.danger)
                        .accessibilityLabel("上次运行有错误")
                }
                Text(job.enabled ? "启用" : "已暂停")
                    .font(.footnote)
                    .foregroundStyle(job.enabled ? Palette.success : Palette.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            jobs = try await appState.performAdmin { client, config in
                try await client.cronJobs(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "定时任务没读出来，可能是网络或服务暂时没响应"
        }
    }
}

/// 任务详情：信息、动作（暂停/恢复/触发/编辑/删除）、运行记录。
struct CronJobDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let job: CronJob
    var onChange: () -> Void = {}

    @State private var current: CronJob
    @State private var runs: [ServerSession] = []
    @State private var runsError: String?
    @State private var notice: String?
    @State private var isTriggering = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    /// 错误原文折叠态（§123 N2）：正文位只显摘要，
    /// 全文收进「原始信息（排障用）」折叠、默认收起
    @State private var showErrorRaw = false

    init(job: CronJob, onChange: @escaping () -> Void = {}) {
        self.job = job
        self.onChange = onChange
        _current = State(initialValue: job)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                summaryGroup
                if hasDetailRows {
                    infoGroup
                }
                actionsGroup
                runsGroup
                dangerGroup
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
        .navigationTitle(current.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRuns() }
        .sheet(isPresented: $showEdit) {
            CronJobFormView(job: current) {
                Task { await reloadJob() }
            }
        }
        .confirmationDialog(
            "删除这个定时任务？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await deleteJob() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("任务与它的计划将被删除，运行记录保留在服务端会话里。")
        }
    }

    /// 附则（卡 15）：状态/计划/下次运行升摘要卡置顶
    private var summaryGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("任务")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                LabeledContent("状态", value: current.enabled ? "启用" : "已暂停")
                GroupDivider()
                LabeledContent("计划") {
                    Text(current.scheduleText)
                        .font(.system(.callout, design: .monospaced))
                }
                if let next = AdminFormat.iso(current.nextRunAt) {
                    GroupDivider()
                    LabeledContent("下次运行", value: AdminFormat.short(next))
                }
            }
            .odGroup()
        }
    }

    /// 详情组有行才渲染（前三行升摘要卡后，空组不留壳）
    private var hasDetailRows: Bool {
        current.lastRunAt != nil
            || (current.deliver?.isEmpty == false)
            || (current.model?.isEmpty == false)
            || (current.prompt?.isEmpty == false)
            || (current.lastError?.isEmpty == false)
    }

    private var infoGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("详情")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if let last = AdminFormat.iso(current.lastRunAt) {
                    GroupDivider()
                    LabeledContent("上次运行", value: AdminFormat.short(last))
                }
                if let deliverText = CronPresentation.deliverLabel(
                    current.deliver
                ) {
                    GroupDivider()
                    // §123（N2）：投递目标走值域译名，
                    // 原始 deliver 值（origin/local/平台
                    // :会话 id）不上行面
                    LabeledContent("投递到", value: deliverText)
                }
                if let model = current.model, !model.isEmpty {
                    GroupDivider()
                    LabeledContent("模型") {
                        // 0.4.0（审计 §3.3 #7）：只读行走显示
                        // 名映射，未知 id 回落原文
                        Text(ModelDisplayNames.displayName(for: model) ?? model)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                if let prompt = current.prompt, !prompt.isEmpty {
                    GroupDivider()
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                        Text("指令")
                            .font(.callout)
                            .foregroundStyle(Palette.inkSecondary)
                        Text(prompt)
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = current.lastError, !error.isEmpty {
                    GroupDivider()
                    // §123（N2）：错误正文位只留摘要（原文
                    // 第一行限长，Core CronPresentation），
                    // 全文进折叠——长堆栈不再整段直铺主区
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingXS
                    ) {
                        HStack(
                            alignment: .top,
                            spacing: OneDayMetrics.spacingS
                        ) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.danger)
                                .accessibilityHidden(true)
                            Text(CronPresentation.errorSummary(error))
                                .font(.subheadline)
                                .foregroundStyle(Palette.ink)
                        }
                        Button {
                            showErrorRaw.toggle()
                        } label: {
                            HStack(
                                spacing: OneDayMetrics.spacingXS
                            ) {
                                Text("原始信息（排障用）")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSecondary)
                                Image(
                                    systemName: showErrorRaw
                                        ? "chevron.up" : "chevron.down"
                                )
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Palette.inkMuted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.odPressable)
                        if showErrorRaw {
                            Text(error)
                                .font(.footnote)
                                .monospaced()
                                .foregroundStyle(Palette.inkSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .odGroup()
        }
    }

    private var actionsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("动作")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                actionRow(
                    title: current.enabled ? "暂停" : "恢复",
                    icon: current.enabled ? "pause.circle" : "play.circle"
                ) {
                    Task { await togglePause() }
                }
                GroupDivider()
                actionRow(
                    title: isTriggering ? "触发中（等任务跑完）…" : "立即触发一次",
                    icon: "play.circle"
                ) {
                    Task { await trigger() }
                }
                .disabled(isTriggering)
                GroupDivider()
                actionRow(title: "编辑", icon: "pencil.circle") {
                    showEdit = true
                }
            }
            .odGroup()
        }
    }

    private var runsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("运行记录")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if runs.isEmpty {
                    Text(runsError ?? "还没有运行记录")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                }
                ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                    if index > 0 {
                        GroupDivider()
                    }
                    runRow(run)
                }
            }
            .odGroup()
        }
    }

    private func runRow(_ run: ServerSession) -> some View {
        // 0.4.0（§3.4）：运行记录点按改道聊天页续聊（运行
        // 记录本体即服务端会话），不再进只读详情页
        Button {
            appState.pendingChatSessionID = run.id
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(AdminFormat.short(run.startedDate))
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Text(runSubtitle(run))
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    private func runSubtitle(_ run: ServerSession) -> String {
        var parts: [String] = []
        // §123（N2）：结束原因走全集映射，未知值落
        // 「已结束」兜底——ws_orphan_reap 等内部原值
        // 不再直印副题
        if let reasonText = CronPresentation.endReasonLabel(
            run.endReason
        ) {
            parts.append(reasonText)
        }
        if let count = run.messageCount {
            parts.append("\(count) 条消息")
        }
        if let start = run.startedDate, let end = run.endedDate {
            let seconds = Int(end.timeIntervalSince(start))
            if seconds >= 0 {
                parts.append("耗时 \(seconds) 秒")
            }
        }
        return parts.isEmpty ? "运行记录" : parts.joined(separator: " · ")
    }

    private var dangerGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("危险操作")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack {
                        Text("删除任务")
                            .font(.body)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.odPressable)
            }
            .odGroup()
        }
    }

    // （infoRow 已于 0.4.0 删除，审计 §3.1：键值行统一 LabeledContent）

    private func actionRow(
        title: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
    }

    // MARK: - 数据与动作

    private func loadRuns() async {
        do {
            runs = try await appState.performAdmin { client, config in
                try await client.cronRuns(config: config, id: current.id, limit: 20)
            }
        } catch {
            runsError = "运行记录没读出来，可能是网络或服务暂时没响应"
        }
    }

    private func reloadJob() async {
        if let jobs = try? await appState.performAdmin({ client, config in
            try await client.cronJobs(config: config)
        }), let fresh = jobs.first(where: { $0.id == current.id }) {
            current = fresh
        }
        onChange()
    }

    private func togglePause() async {
        do {
            if current.enabled {
                try await appState.performAdmin { client, config in
                    try await client.pauseCronJob(config: config, id: current.id)
                }
            } else {
                try await appState.performAdmin { client, config in
                    try await client.resumeCronJob(config: config, id: current.id)
                }
            }
            await reloadJob()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "操作失败，请稍后再试。"
        }
    }

    private func trigger() async {
        isTriggering = true
        defer { isTriggering = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.triggerCronJob(config: config, id: current.id)
            }
            notice = "已触发并执行完成。"
            await loadRuns()
            await reloadJob()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "触发失败，请稍后再试。"
        }
    }

    private func deleteJob() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteCronJob(config: config, id: current.id)
            }
            onChange()
            dismiss()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}

/// 定时任务表单：新建（POST）与编辑（PUT updates）共用。
/// 计划字段收 cron 表达式字符串，附常用预设一键填入。
struct CronJobFormView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let job: CronJob?
    var onSaved: () -> Void = {}

    @State private var name: String
    @State private var prompt: String
    @State private var schedule: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(job: CronJob?, onSaved: @escaping () -> Void = {}) {
        self.job = job
        self.onSaved = onSaved
        _name = State(initialValue: job?.name ?? "")
        _prompt = State(initialValue: job?.prompt ?? "")
        // 编辑态预填：schedule 是字符串时原样，对象时用展示串
        // 兜底（服务端能解析展示串之外的表达式才建议改动）
        if case .string(let raw) = job?.scheduleRaw {
            _schedule = State(initialValue: raw)
        } else {
            _schedule = State(initialValue: job?.scheduleDisplay ?? "")
        }
    }

    private var isValid: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !schedule.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("任务")
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        FieldRow(label: "名称（可选）") {
                            TextField("如：节点巡检", text: $name)
                        }
                        GroupDivider()
                        FieldRow(label: "指令") {
                            TextField("要 Hermes 执行的事", text: $prompt, axis: .vertical)
                                .lineLimit(2...5)
                        }
                        GroupDivider()
                        FieldRow(label: "计划（cron 表达式）") {
                            TextField("0 9 * * *", text: $schedule)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .odGroup()
                    HStack(spacing: OneDayMetrics.spacingS) {
                        presetButton("每小时", "0 * * * *")
                        presetButton("每天 9 点", "0 9 * * *")
                        presetButton("每周一 9 点", "0 9 * * 1")
                    }
                    .padding(.top, OneDayMetrics.spacingM)
                    if let errorMessage {
                        InlineError(errorMessage)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle(job == nil ? "新建定时任务" : "编辑定时任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func presetButton(_ title: String, _ expression: String) -> some View {
        Button(title) {
            schedule = expression
        }
        .buttonStyle(.odSecondary)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchedule = schedule.trimmingCharacters(in: .whitespaces)
        do {
            if let job {
                var updates: [String: JSONValue] = [
                    "prompt": .string(trimmedPrompt),
                    "schedule": .string(trimmedSchedule),
                ]
                updates["name"] = .string(trimmedName)
                try await appState.performAdmin { client, config in
                    try await client.updateCronJob(
                        config: config, id: job.id, updates: updates
                    )
                }
            } else {
                _ = try await appState.performAdmin { client, config in
                    try await client.createCronJob(
                        config: config,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        prompt: trimmedPrompt,
                        schedule: trimmedSchedule,
                        deliver: nil
                    )
                }
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }
}
