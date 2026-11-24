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

    @State private var showCreate = false
    @State private var showBlueprints = false

    /// 名单走共享 CronStore（台账 198 收敛·普查
    /// R4/D2）：与枢纽定时段、状态页摘录同一份取数
    /// 与缓存，本页不再自拉自存
    private var store: CronStore { appState.sharedCronStore() }
    private var jobs: [CronJob] { store.jobs }

    /// 接入组行（与技能页商店行同形：标题＋说明＋箭头）
    private func accessRow(title: String, detail: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            DisclosureChevron(font: .system(size: FrameworkIcon.smallGlyphSize, weight: .regular))
        }
        .contentShape(Rectangle())
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !jobs.isEmpty {
                    // 0.3.7 卡 15：摘要卡＋按状态两组
                    summaryCard
                    jobGroup(title: "开着的", jobs: jobs.filter(\.enabled))
                    jobGroup(title: "停着的", jobs: jobs.filter { !$0.enabled })
                } else if !store.hasLoaded, let errorMessage = store.errorMessage {
                    InlineError(errorMessage)
                    Button("重试") { Task { await store.refresh() } }
                        .buttonStyle(.odSecondary)
                        .padding(.top, OneDayMetrics.spacingSM)
                } else if !store.hasLoaded {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取任务…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.top, OneDayMetrics.spacingL)
                } else {
                    ODEmptyState(
                        "还没有定时任务",
                        systemImage: "clock.arrow.2.circlepath",
                        description: "点右上角新建，让 Hermes 按计划自动干活。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                }
                // 接入组（H11/H13，DESIGN §390）：外部事件
                // 与钩子只读——与定时任务同属自动化面
                SectionLabel("接入")
                    .padding(.top, OneDayMetrics.sectionOuterSpacing)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    NavigationLink {
                        WebhooksView()
                    } label: {
                        accessRow(
                            title: "外部事件",
                            detail: "GitHub、监控、表单的事件直达触发 Hermes"
                        )
                    }
                    .buttonStyle(.odPressable)
                    GroupDivider()
                    NavigationLink {
                        OpsHooksView()
                    } label: {
                        accessRow(
                            title: "钩子",
                            detail: "服务器上已配的自动命令，只看不改"
                        )
                    }
                    .buttonStyle(.odPressable)
                }
                .odGroup()
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
                Button("模板") { showBlueprints = true }
                    .accessibilityLabel("从模板新建定时任务")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CronRelationGraphView()
                } label: {
                    Image(
                        systemName:
                            "point.3.connected.trianglepath.dotted"
                    )
                }
                .accessibilityLabel("关系图")
            }
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
                Task { await store.refresh() }
            }
        }
        .sheet(isPresented: $showBlueprints) {
            CronBlueprintPickerView {
                Task { await store.refresh() }
            }
        }
        .refreshable { await store.refresh() }
        .task { await store.loadIfNeeded() }
        .onAppear {
            // 总览快捷动作深链：消费「新建」请求
            if appState.router.cronCreateRequested {
                appState.router.cronCreateRequested = false
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
                    .padding(.top, OneDayMetrics.sectionOuterSpacing)
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
                Task { await store.refresh() }
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
                        .font(.system(size: FrameworkIcon.composerGlyphSize))
                        .foregroundStyle(Palette.danger)
                        .accessibilityLabel("上次运行有错误")
                }
                Text(job.enabled ? "启用" : "已暂停")
                    .font(.footnote)
                    .foregroundStyle(job.enabled ? Palette.successText : Palette.inkSecondary)
                DisclosureChevron(font: .system(size: FrameworkIcon.smallGlyphSize, weight: .regular))
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingS)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
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
    /// （键值行走 KeyValueRow，台账 198 收敛 S5）
    private var summaryGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("任务")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                KeyValueRow("状态", value: current.enabled ? "启用" : "已暂停")
                GroupDivider()
                KeyValueRow("计划", value: current.scheduleText)
                if let next = AdminFormat.iso(current.nextRunAt) {
                    GroupDivider()
                    KeyValueRow("下次运行", value: AdminFormat.short(next))
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

    /// 详情组块集（台账 198 收敛 S5）：原实现每块以
    /// GroupDivider 开头——首块在位时卡顶悬一条发丝
    /// 线；改块集枚举＋索引分隔（与 CronJobsView 组
    /// 内同式），线只出现在块间。键值块走 KeyValueRow
    private enum InfoBlock {
        case keyValue(label: String, value: String)
        case prompt(String)
        case error(String)
    }

    private var infoBlocks: [InfoBlock] {
        var blocks: [InfoBlock] = []
        if let last = AdminFormat.iso(current.lastRunAt) {
            blocks.append(.keyValue(label: "上次运行", value: AdminFormat.short(last)))
        }
        // §123（N2）：投递目标走值域译名，原始
        // deliver 值（origin/local/平台:会话 id）不上行面
        if let deliverText = CronPresentation.deliverLabel(current.deliver) {
            blocks.append(.keyValue(label: "投递到", value: deliverText))
        }
        if let model = current.model, !model.isEmpty {
            // 0.4.0（审计 §3.3 #7）：只读行走显示名
            // 映射，未知 id 回落原文
            blocks.append(.keyValue(
                label: "模型",
                value: ModelDisplayNames.displayName(for: model) ?? model
            ))
        }
        if let prompt = current.prompt, !prompt.isEmpty {
            blocks.append(.prompt(prompt))
        }
        if let error = current.lastError, !error.isEmpty {
            blocks.append(.error(error))
        }
        return blocks
    }

    private var infoGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("详情")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(Array(infoBlocks.enumerated()), id: \.offset) { index, block in
                    if index > 0 {
                        GroupDivider()
                    }
                    infoBlockView(block)
                }
            }
            .odGroup()
        }
    }

    @ViewBuilder
    private func infoBlockView(_ block: InfoBlock) -> some View {
        switch block {
        case let .keyValue(label, value):
            KeyValueRow(label, value: value)
        case let .prompt(prompt):
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
        case let .error(error):
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
                        .font(.system(size: FrameworkIcon.composerGlyphSize))
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
                        .font(.system(size: FrameworkIcon.badgeGlyphSize, weight: .regular))
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

    private var actionsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("动作")
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
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
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
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
            appState.router.pendingChatSessionID = run.id
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
                DisclosureChevron(font: .system(size: FrameworkIcon.smallGlyphSize, weight: .regular))
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
                .padding(.top, OneDayMetrics.sectionOuterSpacing)
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

    // （键值行沿革：infoRow（0.4.0 删）→ LabeledContent
    // → KeyValueRow（台账 198 收敛 S5：组卡内键值行单源件））

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

    /// 动作后取鲜（台账 198 收敛）：全量重拉改走共享
    /// CronStore——本页取鲜值的同时枢纽段/状态页摘录
    /// 同帧同步，不再各拉一份
    private func reloadJob() async {
        let store = appState.sharedCronStore()
        await store.refresh()
        if let fresh = store.jobs.first(where: { $0.id == current.id }) {
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
    /// 新建建成回执（§459 点子建为例行用）：只在新建
    /// 分支、服务端回执到手时以新 job 本体回调，供调
    /// 用方做名单回读确认；编辑分支不触发
    var onCreated: (CronJob) -> Void = { _ in }

    @State private var name: String
    @State private var prompt: String
    @State private var schedule: String
    /// 投递目标（§388 H6）：服务端单源拉取，""＝不指定
    /// （沿服务端默认）；拉不到时只剩「默认」一档、不假造
    @State private var deliveryTargets: [CronDeliveryTarget] = []
    @State private var selectedDeliver: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        job: CronJob?,
        onSaved: @escaping () -> Void = {},
        prefillName: String = "",
        prefillPrompt: String = "",
        onCreated: @escaping (CronJob) -> Void = { _ in }
    ) {
        self.job = job
        self.onSaved = onSaved
        self.onCreated = onCreated
        _name = State(initialValue: job?.name ?? prefillName)
        _prompt = State(initialValue: job?.prompt ?? prefillPrompt)
        _selectedDeliver = State(initialValue: job?.deliver ?? "")
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
                    SectionLabel("投递")
                        .padding(.top, OneDayMetrics.spacingL)
                        .padding(.bottom, OneDayMetrics.spacingS)
                    VStack(spacing: 0) {
                        FieldRow(label: "投递目标") {
                            Picker("", selection: $selectedDeliver) {
                                Text("默认（按服务器设置）").tag("")
                                ForEach(deliveryTargets) { target in
                                    Text(deliveryTargetTitle(target))
                                        .tag(target.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                    }
                    .odGroup()
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
            .task { await loadDeliveryTargets() }
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
        .fullscreenPopBridge()
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
                // 投递目标改了才带（清空回默认的语义服务端
                // 未定，只许改到具体目标、不许假装能清空）
                if !selectedDeliver.isEmpty,
                   selectedDeliver != (job.deliver ?? "") {
                    updates["deliver"] = .string(selectedDeliver)
                }
                try await appState.performAdmin { client, config in
                    try await client.updateCronJob(
                        config: config, id: job.id, updates: updates
                    )
                }
            } else {
                let created = try await appState.performAdmin {
                    client, config in
                    try await client.createCronJob(
                        config: config,
                        name: trimmedName.isEmpty ? nil : trimmedName,
                        prompt: trimmedPrompt,
                        schedule: trimmedSchedule,
                        deliver: selectedDeliver.isEmpty
                            ? nil : selectedDeliver
                    )
                }
                onCreated(created)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }

    /// 投递目标行题：名字＋未设主频道的如实标注
    private func deliveryTargetTitle(_ target: CronDeliveryTarget) -> String {
        if let note = target.availabilityNote {
            return "\(target.name)（\(note)）"
        }
        return target.name
    }

    /// 投递目标取数：失败静默降级为仅「默认」一档（表单
    /// 本体可用优先，不拿投递名单的失败拦住建任务）
    private func loadDeliveryTargets() async {
        guard deliveryTargets.isEmpty else { return }
        if let targets = try? await appState.performAdmin({ client, config in
            try await client.cronDeliveryTargets(config: config)
        }) {
            deliveryTargets = targets
        }
    }
}
