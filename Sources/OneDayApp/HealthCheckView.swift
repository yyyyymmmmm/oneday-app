import OneDayDesign
import OneDayCore
import SwiftUI

/// 体检面（H1-a 体检段＋H1-b 存档段＋H1-d 身份对
/// 账组，台账 158）：设置 → 服务器管理 → 维护 →
/// 「体检与存档」。体检段——自检（doctor）＋安全
/// 审计（security-audit）两组依次跑、出人话结论、
/// 留摘要痕；第四组身份对账（H1-d）把认领三项落
/// 成只读核对（主线绑定/消息路由/会话目录），取
/// 不到数据的项如实降级「暂无法对账」；存档段——
/// 备份（同为 spawn＋poll、三态判读）＋检查点如
/// 实呈现＋升级前检查单联动行。诊断段（H1-c，探
/// 活实证服务端只有外发形态、已缓办）不在本面出
/// 现，不留假按钮；检查点清理（prune）行为未知，
/// 同样不放行。
/// 数据口径：结论全部来自 HealthCheckStore 本轮解析
/// 结果与 HealthSummaryStore 留痕，两处同源；状态页
/// 的「看现在」与本面的「跑一遍查问题」分工不混。
struct HealthCheckView: View {
    @Environment(AppState.self) private var appState
    @State private var store = HealthCheckStore()
    @State private var summaryStore = HealthSummaryStore.shared
    @State private var archiveStore = ArchiveStore()
    @State private var backupRecordStore = BackupRecordStore.shared

    var body: some View {
        List {
            conclusionSection
            runButtonSection
            doctorSection
            auditSection
            identitySection
            archiveSection
            checkpointsSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("体检与存档")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await archiveStore.loadCheckpointsIfNeeded(
                appState: appState
            )
        }
    }

    // MARK: - 结论卡

    private var savedSummary: HealthCheckSummary? {
        summaryStore.summary(for: appState.config?.baseString)
    }

    @ViewBuilder
    private var conclusionSection: some View {
        Section {
            if store.isRunning {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ProgressView()
                    Text("正在体检…")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else if let summary = savedSummary {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingS
                ) {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        StatusDot(color: verdictColor(summary.overall))
                        Text(summary.headline)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                    Text(
                        "上次体检 · "
                            + DisplayDate.relativeDateTime(
                                summary.date
                            )
                    )
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    if let doctor = summary.doctor {
                        groupLine(name: "自检", summary: doctor)
                    }
                    if let audit = summary.audit {
                        groupLine(name: "安全", summary: audit)
                    }
                    if let identity = summary.identity {
                        groupLine(name: "身份", summary: identity)
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingS)
            } else {
                OneDayDesign.EmptyState(
                    icon: "stethoscope",
                    title: "还没做过体检",
                    message: "跑一次体检，看看服务器的健康与安全状况。"
                )
                .padding(.vertical, OneDayMetrics.spacingM)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func groupLine(
        name: String, summary: HealthGroupSummary
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            StatusDot(color: verdictColor(summary.verdict))
            Text(name)
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
            Text(summary.headline)
                .font(.rowSubtitle)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer(minLength: OneDayMetrics.spacingS)
        }
    }

    // MARK: - 开始按钮

    private var runButtonSection: some View {
        Section {
            Button {
                Task { await store.runAll(appState: appState) }
            } label: {
                HStack {
                    Spacer()
                    if store.isRunning {
                        ProgressView()
                            .padding(.trailing, OneDayMetrics.spacingS)
                        Text("体检中…")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.surface)
                    } else {
                        Text(savedSummary == nil ? "跑一次体检" : "开始体检")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.surface)
                    }
                    Spacer()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
            .disabled(!store.canStart)
            .listRowBackground(
                store.canStart ? Palette.ink : Palette.inkMuted
            )
            .listRowInsets(settingsRowInsets)
        }
    }

    // MARK: - 自检组

    private var doctorSection: some View {
        Section {
            groupStatusRow(
                action: .doctor,
                idleText: "检查服务器自身的配置、环境与依赖"
            )
            if case .failed = store.doctorPhase {
                retryRow(.doctor)
            }
            if let run = store.doctorRun {
                doctorCountsRow(run)
                if let reason = run.incompleteReason {
                    Text(reason)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
                doctorDetailRow(run)
            }
        } header: {
            sectionHeader("自检")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func doctorCountsRow(_ run: DoctorRun) -> some View {
        Text(
            "通过 \(run.passCount) · 注意 \(run.warnCount)"
                + " · 异常 \(run.failCount)"
        )
        .font(.rowSubtitle)
        .foregroundStyle(Palette.inkSecondary)
    }

    /// 明细折叠：分组人话名＋三档计数，异常/注意项逐
    /// 条呈原文，崩溃异常行原文垫底（结论人话、明细
    /// 原文——探活 §四的折中口径）
    private func doctorDetailRow(_ run: DoctorRun) -> some View {
        DisclosureGroup("查看明细") {
            ForEach(
                Array(run.sections.enumerated()), id: \.offset
            ) { _, section in
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingXS
                ) {
                    Text(
                        "\(section.displayTitle) · 通过 \(section.passCount)"
                            + " · 注意 \(section.warnCount)"
                            + " · 异常 \(section.failCount)"
                    )
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    ForEach(
                        Array(
                            section.items
                                .filter { $0.level != .pass }
                                .enumerated()
                        ),
                        id: \.offset
                    ) { _, item in
                        HStack(
                            alignment: .top,
                            spacing: OneDayMetrics.spacingS
                        ) {
                            Text(item.level == .warn ? "⚠" : "✗")
                                .foregroundStyle(
                                    item.level == .warn
                                        ? Palette.warning : Palette.danger
                                )
                            VStack(
                                alignment: .leading,
                                spacing: OneDayMetrics.spacingMicro
                            ) {
                                Text(item.text)
                                    .font(.rowSubtitle)
                                    .foregroundStyle(Palette.ink)
                                ForEach(
                                    Array(item.details.enumerated()),
                                    id: \.offset
                                ) { _, detail in
                                    Text(detail)
                                        .font(.rowSubtitle)
                                        .foregroundStyle(
                                            Palette.inkSecondary
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
            if let errorLine = run.crashErrorLine {
                Text(errorLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .font(.rowTitleL)
        .foregroundStyle(Palette.ink)
    }

    // MARK: - 安全组

    private var auditSection: some View {
        Section {
            groupStatusRow(
                action: .securityAudit,
                idleText: "检查已知漏洞与修复版本"
            )
            if case .failed = store.auditPhase {
                retryRow(.securityAudit)
            }
            if let run = store.auditRun, !run.findings.isEmpty {
                ForEach(
                    Array(run.findings.enumerated()), id: \.offset
                ) { _, finding in
                    findingRow(finding)
                }
            }
        } header: {
            sectionHeader("安全")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func findingRow(_ finding: AuditFinding) -> some View {
        VStack(
            alignment: .leading, spacing: OneDayMetrics.spacingMicro
        ) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(finding.severity.word)
                    .font(.rowSubtitle)
                    .foregroundStyle(severityColor(finding.severity))
                Text(finding.packageName)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let version = finding.installedVersion {
                    Text(version)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            if let fixed = finding.fixedIn {
                Text("可升级到 \(fixed) 修复")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if let ghsa = finding.ghsa {
                Text(ghsa)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    // MARK: - 身份对账组（H1-d）

    /// 体检第四组：认领三项只读核对（主线绑定/消息
    /// 路由/会话目录）逐项呈现——状态点＋人话结论＋
    /// （不一致时）哪边为准的提示。当前档案只报服务
    /// 端现行值、不参与判定（App 侧没有第二真源，不
    /// 造假对账），单列一行说明白。
    private var identitySection: some View {
        Section {
            identityStatusRow
            if case .failed = store.identityPhase {
                Button {
                    Task {
                        await store.retryIdentity(appState: appState)
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Palette.ink)
                            .accessibilityHidden(true)
                        Text("重试这一项")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: OneDayMetrics.spacingS)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                    .contentShape(Rectangle())
                }
                .disabled(!store.canStart)
            }
            if let run = store.identityRun {
                ForEach(
                    Array(run.items.enumerated()), id: \.offset
                ) { _, item in
                    identityItemRow(item)
                }
                if let profile = run.currentProfile {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text("当前档案")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Text(profile)
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                    Text("档案以服务端为准，这里只报现行值，不参与对账判定。")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        } header: {
            sectionHeader("身份对账")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    /// 身份组状态行（与两组同式四态）：跑中/结论/
    /// 失败/未跑（有留痕读留痕、无留痕显说明）
    @ViewBuilder
    private var identityStatusRow: some View {
        switch store.identityPhase {
        case .running(let since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ProgressView()
                    Text(
                        "正在对账… 已用 "
                            + "\(Int(context.date.timeIntervalSince(since))) 秒"
                    )
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        case .finished:
            if let run = store.identityRun {
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: verdictColor(run.verdict))
                    Text(run.headline)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        case .failed(let message):
            HStack(spacing: OneDayMetrics.spacingS) {
                StatusDot(color: Palette.warning)
                Text(message)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        case .idle:
            if let group = savedSummary?.identity {
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: verdictColor(group.verdict))
                    Text(group.headline)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else {
                Text("核对主线绑定、消息路由与会话目录对不对得上")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        }
    }

    private func identityItemRow(_ item: IdentityItem) -> some View {
        HStack(
            alignment: .top, spacing: OneDayMetrics.spacingS
        ) {
            StatusDot(color: verdictColor(item.verdict))
                .padding(.top, OneDayMetrics.spacingXS)
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(item.title)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                Text(item.headline)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                if let note = item.authorityNote {
                    Text(note)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    // MARK: - 存档段（H1-b）

    private var archiveSection: some View {
        Section {
            readinessRow
            backupStatusRow
            backupButtonRow
        } header: {
            sectionHeader("存档")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    /// 升级前检查单联动行（存档段顶部）：新鲜备份＋
    /// 体检留痕合成一句人话判断，只呈现、不执行升级
    private var readinessRow: some View {
        let readiness = ArchiveReadinessJudge.judge(
            backup: backupRecordStore.record(
                for: appState.config?.baseString
            ),
            health: savedSummary,
            now: Date()
        )
        return HStack(spacing: OneDayMetrics.spacingS) {
            StatusDot(
                color: readiness.ready
                    ? Palette.success : Palette.warning
            )
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text("升级前检查")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                Text(readiness.headline)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    /// 备份状态行：跑中（进度＋已用时）／本轮判读／
    /// 引擎失败（人话原因，下方按钮即重试）／未跑
    /// （有留痕读留痕、无留痕显说明）
    @ViewBuilder
    private var backupStatusRow: some View {
        switch archiveStore.backupPhase {
        case .running(let since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ProgressView()
                    Text(
                        "正在备份… 已用 "
                            + "\(Int(context.date.timeIntervalSince(since))) 秒"
                    )
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        case .finished:
            if let run = archiveStore.backupRun {
                backupResultRows(
                    headline: run.headline,
                    state: run.state,
                    archiveName: run.archiveName,
                    caption: nil
                )
            }
        case .failed(let message):
            HStack(spacing: OneDayMetrics.spacingS) {
                StatusDot(color: Palette.warning)
                Text(message)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        case .idle:
            if let record = backupRecordStore.record(
                for: appState.config?.baseString
            ) {
                backupResultRows(
                    headline: record.headline,
                    state: record.state,
                    archiveName: record.archiveName,
                    caption: "上次备份 · "
                        + DisplayDate.relativeDateTime(record.date)
                )
            } else {
                Text("还没备过份——备份会在服务器上生成一份完整存档")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        }
    }

    private func backupResultRows(
        headline: String, state: BackupRun.State,
        archiveName: String?, caption: String?
    ) -> some View {
        VStack(
            alignment: .leading, spacing: OneDayMetrics.spacingMicro
        ) {
            HStack(spacing: OneDayMetrics.spacingS) {
                StatusDot(color: backupStateColor(state))
                Text(headline)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            if let caption {
                Text(caption)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            if let archiveName {
                Text(archiveName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private var backupButtonRow: some View {
        Button {
            Task {
                await archiveStore.runBackup(appState: appState)
                // 备份完成后顺手刷新检查点呈现（同一件
                // 「存档现状」，不让用户看旧数）
                await archiveStore.loadCheckpoints(
                    appState: appState
                )
            }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "archivebox")
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
                Text("立即备份")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .disabled(!archiveStore.canStartBackup)
    }

    private func backupStateColor(
        _ state: BackupRun.State
    ) -> Color {
        switch state {
        case .clean: return Palette.success
        case .attention: return Palette.warning
        case .failed: return Palette.danger
        }
    }

    // MARK: - 检查点段（H1-b）

    /// 检查点如实呈现：现役实例恒空就是「暂无检查
    /// 点」的诚实空状态；不做假数据、不当新鲜度数
    /// 据源；清理（prune）不放行——本段没有清理按钮。
    private var checkpointsSection: some View {
        Section {
            switch archiveStore.checkpointsPhase {
            case .failed(let message):
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: Palette.warning)
                    Text(message)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                Button {
                    Task {
                        await archiveStore.loadCheckpoints(
                            appState: appState
                        )
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Palette.ink)
                            .accessibilityHidden(true)
                        Text("重新读取")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: OneDayMetrics.spacingS)
                    }
                    .frame(
                        minHeight: OneDayMetrics.settingsRowHeight
                    )
                    .contentShape(Rectangle())
                }
            case .finished:
                if let checkpoints = archiveStore.checkpoints {
                    if checkpoints.isEmpty {
                        OneDayDesign.EmptyState(
                            icon: "clock.arrow.circlepath",
                            title: "暂无检查点",
                            message: "这台服务器上还没有检查点记录。"
                        )
                        .padding(.vertical, OneDayMetrics.spacingM)
                    } else {
                        ForEach(
                            Array(
                                checkpoints.sessions.enumerated()
                            ),
                            id: \.offset
                        ) { _, session in
                            checkpointRow(session)
                        }
                        Text(
                            "共 \(checkpoints.sessions.count) 个会话 · "
                                + ByteCountFormatter.string(
                                    fromByteCount: Int64(
                                        checkpoints.totalBytes
                                    ),
                                    countStyle: .file
                                )
                        )
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                    }
                }
            case .idle, .running:
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ProgressView()
                    Text("正在读取检查点…")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        } header: {
            sectionHeader("检查点")
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(settingsRowInsets)
    }

    private func checkpointRow(
        _ session: CheckpointsResponse.Session
    ) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(session.session)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("\(session.files) 个文件")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(
                ByteCountFormatter.string(
                    fromByteCount: Int64(session.bytes),
                    countStyle: .file
                )
            )
            .font(.rowSubtitle)
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    // MARK: - 组状态行（两组共用）

    /// 组状态一行的四态呈现：跑中（进度＋已用时）／
    /// 本轮结论／失败（人话原因）／未跑（有留痕读留
    /// 痕、无留痕显说明）
    @ViewBuilder
    private func groupStatusRow(
        action: HealthAction, idleText: String
    ) -> some View {
        switch store.phase(for: action) {
        case .running(let since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: OneDayMetrics.spacingSM) {
                    ProgressView()
                    Text(
                        "正在检查… 已用 "
                            + "\(Int(context.date.timeIntervalSince(since))) 秒"
                    )
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        case .finished:
            if let headline = sessionHeadline(for: action),
               let verdict = sessionVerdict(for: action) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: verdictColor(verdict))
                    Text(headline)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        case .failed(let message):
            HStack(spacing: OneDayMetrics.spacingS) {
                StatusDot(color: Palette.warning)
                Text(message)
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        case .idle:
            if let group = savedGroup(for: action) {
                HStack(spacing: OneDayMetrics.spacingS) {
                    StatusDot(color: verdictColor(group.verdict))
                    Text(group.headline)
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } else {
                Text(idleText)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        }
    }

    private func retryRow(_ action: HealthAction) -> some View {
        Button {
            Task { await store.retry(action, appState: appState) }
        } label: {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Palette.ink)
                    .accessibilityHidden(true)
                Text("重试这一项")
                    .font(.rowTitleL)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
            .contentShape(Rectangle())
        }
        .disabled(!store.canStart)
    }

    private func sessionHeadline(for action: HealthAction) -> String? {
        switch action {
        case .doctor: return store.doctorRun?.headline
        case .securityAudit: return store.auditRun?.headline
        }
    }

    private func sessionVerdict(for action: HealthAction) -> HealthVerdict? {
        switch action {
        case .doctor: return store.doctorRun?.verdict
        case .securityAudit: return store.auditRun?.verdict
        }
    }

    private func savedGroup(
        for action: HealthAction
    ) -> HealthGroupSummary? {
        switch action {
        case .doctor: return savedSummary?.doctor
        case .securityAudit: return savedSummary?.audit
        }
    }

    // MARK: - 口径件

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private func verdictColor(_ verdict: HealthVerdict) -> Color {
        switch verdict {
        case .ok: return Palette.success
        case .attention: return Palette.warning
        case .problem: return Palette.danger
        case .incomplete: return Palette.inkMuted
        }
    }

    private func severityColor(
        _ severity: AuditFinding.Severity
    ) -> Color {
        switch severity {
        case .critical, .high: return Palette.danger
        case .moderate: return Palette.warning
        case .low: return Palette.inkSecondary
        }
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
