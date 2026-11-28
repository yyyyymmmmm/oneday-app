import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// Git & Worktree 评审工作台（Hermes v0.23.0 `web_routers/git.py`）：
/// 支持宿主机仓库状态查看、未提交变更文件列表、彩色 Diff 审阅、暂存/取消暂存/还原、
/// 一键提交与推送、分支切换以及多 Worktree 创建与清理。
struct GitWorktreeWorkbenchView: View {
    @Environment(AppState.self) private var appState

    @State private var repoPath = "/opt/data"
    @State private var selectedTab = 0
    @State private var status: GitRepoStatus?
    @State private var files: [GitReviewFileItem] = []
    @State private var branches: [GitBranchItem] = []
    @State private var worktrees: [GitWorktreeItem] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var feedbackText: String?

    @State private var diffTarget: GitReviewFileItem?
    @State private var diffContent = ""
    @State private var showCommitSheet = false
    @State private var showAddWorktreeSheet = false

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "arrow.triangle.pull",
                tint: Palette.tintSkyInk,
                title: "Git 与 Worktree 工作台",
                subtitle: "直接审查宿主机仓库的未提交变更、查看文件 Diff、暂存提交推送，并管理多分支与子分身 Worktree。",
                statusText: status.map { $0.branch.isEmpty ? "已加载" : $0.branch } ?? "待加载",
                statusTone: (status?.dirtyCount ?? 0) > 0 ? .warning : .healthy
            )

            Section {
                HStack(spacing: 8) {
                    TextField("仓库路径（如 /opt/data/project）", text: $repoPath)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await refreshAll() } }
                    Button("加载") {
                        Task { await refreshAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } header: {
                SettingsSectionHeader("宿主机仓库路径")
            }
            .listRowBackground(Palette.surface)

            Section {
                Picker("视图", selection: $selectedTab) {
                    Text("变更 (\(files.count))").tag(0)
                    Text("分支 (\(branches.count))").tag(1)
                    Text("Worktree (\(worktrees.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Palette.surface)
            }

            if let feedbackText {
                Section {
                    Label(feedbackText, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            if selectedTab == 0 {
                changesSection
            } else if selectedTab == 1 {
                branchesSection
            } else {
                worktreesSection
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("Git 评审工作台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if selectedTab == 0 {
                    Button {
                        showCommitSheet = true
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel("提交变更")
                } else if selectedTab == 2 {
                    Button {
                        showAddWorktreeSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增 Worktree")
                }
                Button {
                    Task { await refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .refreshable { await refreshAll() }
        .task { await refreshAll() }
        .sheet(item: $diffTarget) { file in
            GitDiffSheet(file: file, diffText: diffContent)
        }
        .sheet(isPresented: $showCommitSheet) {
            GitCommitSheet(repoPath: repoPath) {
                await refreshAll()
                feedbackText = "提交已完成"
            }
        }
        .sheet(isPresented: $showAddWorktreeSheet) {
            GitAddWorktreeSheet(repoPath: repoPath) {
                await refreshAll()
                feedbackText = "已创建新 Worktree"
            }
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        Section {
            if loading && files.isEmpty {
                HStack {
                    ProgressView()
                    Text("正在读取仓库变更…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if files.isEmpty {
                Text("当前工作区干净，没有未提交变更。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(files) { file in
                    Button {
                        Task { await openDiff(file) }
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(
                                symbol: file.staged ? "checkmark.circle.fill" : "doc.badge.ellipsis",
                                color: file.staged ? Palette.tintGreenInk : Palette.tintOrangeInk
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path)
                                    .font(.callout.monospaced())
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Text(file.staged ? "已暂存" : "未暂存")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(file.staged ? Palette.successText : Palette.warningText)
                                    Text(file.status)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(Palette.inkSecondary)
                                    if file.additions > 0 || file.deletions > 0 {
                                        Text("+\(file.additions) -\(file.deletions)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(Palette.inkSecondary)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(file.staged ? "取消暂存" : "暂存") {
                            Task { await toggleStage(file) }
                        }
                        .tint(file.staged ? .orange : .green)

                        Button("还原", role: .destructive) {
                            Task { await revert(file) }
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader("未提交变更（点按查看 Diff，左滑暂存/还原）")
        }
        .listRowBackground(Palette.surface)

        if let status, status.ahead > 0 {
            Section {
                Button {
                    Task { await pushBranch() }
                } label: {
                    Label("推送当前分支（领先远端 \(status.ahead) 个提交）", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Palette.surface)
        }
    }

    @ViewBuilder
    private var branchesSection: some View {
        Section {
            if branches.isEmpty {
                Text("暂无分支信息。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(branches) { branch in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(
                            symbol: branch.isCurrent ? "checkmark.seal.fill" : "arrow.triangle.branch",
                            color: branch.isCurrent ? Palette.tintGreenInk : Palette.tintSkyInk
                        )
                        Text(branch.name)
                            .font(.callout.monospaced())
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if branch.isCurrent {
                            SettingsStatusPill(text: "当前", tone: .healthy)
                        } else {
                            Button("切换") {
                                Task { await switchBranch(branch.name) }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader("本地与追踪分支")
        }
        .listRowBackground(Palette.surface)
    }

    @ViewBuilder
    private var worktreesSection: some View {
        Section {
            if worktrees.isEmpty {
                Text("暂无 Worktree 记录。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(worktrees) { wt in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(wt.branch.isEmpty ? "detached" : wt.branch)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            if wt.isMain {
                                SettingsStatusPill(text: "主工作树", tone: .healthy)
                            }
                            Spacer()
                            if !wt.head.isEmpty {
                                Text(String(wt.head.prefix(7)))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        Text(wt.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 2)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !wt.isMain {
                            Button(role: .destructive) {
                                Task { await removeWorktree(wt) }
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader("Worktree 列表（支持左滑清理）")
        }
        .listRowBackground(Palette.surface)
    }

    private func refreshAll() async {
        let trimmed = repoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        loading = true
        errorText = nil
        defer { loading = false }

        do {
            status = try await appState.performAdmin { client, config in
                try await client.gitStatus(config: config, path: trimmed)
            }
            files = try await appState.performAdmin { client, config in
                try await client.gitReviewList(config: config, path: trimmed, scope: "uncommitted")
            }
            branches = try await appState.performAdmin { client, config in
                try await client.gitBranches(config: config, path: trimmed)
            }
            worktrees = try await appState.performAdmin { client, config in
                try await client.gitWorktrees(config: config, path: trimmed)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openDiff(_ file: GitReviewFileItem) async {
        do {
            diffContent = try await appState.performAdmin { client, config in
                try await client.gitReviewDiff(
                    config: config, path: repoPath, file: file.path, staged: file.staged
                )
            }
            diffTarget = file
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleStage(_ file: GitReviewFileItem) async {
        do {
            try await appState.performAdmin { client, config in
                if file.staged {
                    try await client.gitUnstageFile(config: config, path: repoPath, file: file.path)
                } else {
                    try await client.gitStageFile(config: config, path: repoPath, file: file.path)
                }
            }
            Haptics.success()
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func revert(_ file: GitReviewFileItem) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gitRevertFile(config: config, path: repoPath, file: file.path)
            }
            Haptics.success()
            feedbackText = "已还原 \(file.path)"
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func switchBranch(_ branch: String) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gitSwitchBranch(config: config, path: repoPath, branch: branch)
            }
            Haptics.success()
            feedbackText = "已切换至分支 \(branch)"
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func pushBranch() async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gitPush(config: config, path: repoPath)
            }
            Haptics.success()
            feedbackText = "已推送至远端仓库"
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func removeWorktree(_ wt: GitWorktreeItem) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.gitRemoveWorktree(
                    config: config, path: repoPath, worktreePath: wt.path, force: false
                )
            }
            Haptics.success()
            feedbackText = "已移除 Worktree"
            await refreshAll()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct GitDiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let file: GitReviewFileItem
    let diffText: String

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                Text(diffText.isEmpty ? "（无文本 Diff 内容）" : diffText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Palette.settingsBG)
            .navigationTitle(file.path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct GitCommitSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let repoPath: String
    let onCommitted: () async -> Void

    @State private var message = ""
    @State private var alsoPush = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("提交信息") {
                    TextField("feat: 描述本次改动", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("提交后立即推送至远端", isOn: $alsoPush)
                }
                if let errorText {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("提交变更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "提交中…" : "提交") {
                        Task { await commit() }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
        }
    }

    private func commit() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.gitCommit(
                    config: config, path: repoPath,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    push: alsoPush
                )
            }
            Haptics.success()
            await onCommitted()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct GitAddWorktreeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let repoPath: String
    let onCreated: () async -> Void

    @State private var name = ""
    @State private var branch = ""
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("新 Worktree 参数") {
                    TextField("目录名（如 feat-sandbox）", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("新建分支名（可选）", text: $branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let errorText {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(Palette.danger)
                    }
                }
            }
            .navigationTitle("新增 Worktree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "创建中…" : "创建") {
                        Task { await create() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
        }
    }

    private func create() async {
        busy = true
        errorText = nil
        defer { busy = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.gitAddWorktree(
                    config: config, path: repoPath,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    branch: branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : branch.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            Haptics.success()
            await onCreated()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
