import OneDayCore
import OneDayDesign
import SwiftUI

/// 记忆条目段（0.13.0 P7 客户端先行）：「记忆」页
/// （MemoryView）顶部段，与提供方/文件/重置各段同
/// 页——枢纽记忆卡与设置页记忆行两个入口共用，不
/// 双挂第二入口。契约 memory-bridge-contract-
/// 20261109.md：条目面未开通时如实露「记忆条目尚
/// 未开通」，零假数据；开通后即真列表（设计标准
/// §7 P7 锚：条目行＝标题＋来源 small＋时间）。写
/// 动作只有「发起待批」一途：新建/编辑/遗忘全走
/// MemoriesStore 的 propose，裁决在活动格审批面，
/// 本段只呈状态、不设批准/驳回钮。
struct MemoryEntriesSection: View {
    @Environment(AppState.self) private var appState
    let store: MemoriesStore

    @State private var searchText = ""
    @State private var showingCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("记忆条目")
                Spacer()
                if store.loadState == .ready {
                    Button {
                        store.clearProposeError()
                        showingCreate = true
                    } label: {
                        Label("新建", systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.odPressable)
                    .foregroundStyle(Palette.primary)
                    .disabled(store.memoryGateEnabled == false)
                }
            }
            .padding(.bottom, OneDayMetrics.spacingS)

            switch store.loadState {
            case .loading:
                loadingRow
            case .notConnected(let message):
                stateCard(
                    title: "还没连上你的服务", message: message
                )
            case .sourceNotOpened(let message):
                stateCard(
                    title: "记忆条目尚未开通", message: message
                )
            case .failed(let message):
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                    InlineError(message)
                    Button("重试") {
                        Task { await store.load(appState: appState) }
                    }
                    .buttonStyle(.odSecondary)
                }
            case .ready:
                readyContent
            }
        }
        .padding(.bottom, 28)
        .sheet(isPresented: $showingCreate) {
            MemoryEntryEditorView(store: store, mode: .create)
        }
    }

    private var loadingRow: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            ProgressView()
            Text("正在读取记忆条目…")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 未连接/未开通的诚实状态卡（标题逐字，不摆
    /// 任何合成条目冒充已开通）
    private func stateCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            Button("重新检查") {
                Task { await store.load(appState: appState) }
            }
            .buttonStyle(.odSecondary)
            .padding(.top, OneDayMetrics.spacingXS)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OneDayMetrics.spacingM)
        .odGroup()
    }

    // MARK: - 就绪态

    @ViewBuilder
    private var readyContent: some View {
        if store.memoryGateEnabled == false {
            Text("记忆写入审批未启用：可以看条目，但暂时不能新建、修改或遗忘记忆。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
        }
        if store.hasProposalRows {
            proposalsGroup
        }
        if store.entries.isEmpty {
            EmptyState(
                icon: "brain",
                title: "暂无记忆条目",
                message: "智能体还没有积累可逐条查看的长期记忆。"
            )
            .padding(.vertical, OneDayMetrics.spacingM)
        } else {
            searchField
            let groups = store.groupedEntries(query: searchText)
            if groups.isEmpty {
                Text("没有找到匹配的记忆。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.vertical, OneDayMetrics.spacingS)
            } else {
                ForEach(
                    Array(groups.enumerated()), id: \.offset
                ) { _, group in
                    groupCard(group)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
            TextField("搜索记忆", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.odPressable)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: 40)
        .odGroup()
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    /// 待批区：本会话提案（带落定状态）＋上一会话
    /// 遗留的 App 来源待批；裁决去向统一提示到
    /// 活动格审批面，本区不设裁决钮
    private var proposalsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(store.proposals) { proposal in
                    proposalRow(proposal)
                    GroupDivider()
                }
                ForEach(store.externalPending) { record in
                    externalPendingRow(record)
                    GroupDivider()
                }
                Text("批准或驳回在枢纽的审批区进行（聊天页点顶部胶囊打开）；批准后这里会刷新确认结果。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
            }
            .odGroup()
        }
        .padding(.bottom, OneDayMetrics.spacingS)
    }

    private func proposalRow(_ proposal: MemoryProposal) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text("\(proposal.operation.label) · \(proposal.target.label)")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let note = proposal.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            statusChip(proposal.statusLabel)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func externalPendingRow(_ record: WriteGateRecord) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(record.headline)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("上次打开时提交的，还在等审批。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            statusChip("待审批")
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    /// 待审批 chip（设计标准 §5.12 chip 口径的文字版：
    /// 强调字＋弱面底）
    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, OneDayMetrics.stackGap)
            .background(
                Palette.primaryTint,
                in: Capsule()
            )
    }

    private func groupCard(
        _ group: (target: MemoryTarget, entries: [BridgeMemoryEntry])
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(group.target.label)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                ForEach(
                    Array(group.entries.enumerated()),
                    id: \.element.id
                ) { index, entry in
                    if index > 0 {
                        GroupDivider()
                    }
                    NavigationLink {
                        MemoryEntryDetailView(store: store, entryID: entry.id)
                    } label: {
                        entryRow(entry)
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .odGroup()
        }
        .padding(.bottom, OneDayMetrics.spacingL)
    }

    /// 条目行（§7 P7 锚）：标题＋时间 small；
    /// 来源由分组标题承担；被待批盯上时行尾贴标
    private func entryRow(_ entry: BridgeMemoryEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(MemoryEntryPresentation.displayTitle(of: entry))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text(AdminFormat.short(
                    Date(timeIntervalSince1970: entry.updatedAt)
                ))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if store.hasPendingOperation(entry) {
                statusChip("待审批")
            }
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
}

/// 记忆条目详情：全文＋来源＋文件时刻；动作只有
/// 编辑与遗忘，两者都只发起待批（提交后明示去向），
/// 批准后回读确认才算生效——详情内容永远以服务端
/// 回读为准，不本地改字冒充已改。
struct MemoryEntryDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: MemoriesStore
    let entryID: String

    @State private var showingEditor = false
    @State private var confirmingForget = false

    var body: some View {
        Group {
            if let entry = store.entry(id: entryID) {
                content(entry)
            } else {
                ContentUnavailableView(
                    "这条记忆已不在",
                    systemImage: "brain",
                    description: Text("它可能已经被遗忘或修改了。")
                )
            }
        }
        .navigationTitle("记忆详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDetail(appState: appState, id: entryID)
        }
        .refreshable {
            await store.load(appState: appState)
            await store.loadDetail(appState: appState, id: entryID)
        }
        .sheet(isPresented: $showingEditor) {
            if let entry = store.entry(id: entryID),
               let detail = store.details[entryID] {
                MemoryEntryEditorView(
                    store: store,
                    mode: .edit(entry: entry, currentContent: detail.content)
                )
            }
        }
        .confirmationDialog(
            "遗忘这条记忆？",
            isPresented: $confirmingForget,
            titleVisibility: .visible
        ) {
            Button("提交遗忘（待审批）", role: .destructive) {
                Task {
                    if let entry = store.entry(id: entryID),
                       await store.proposeDelete(
                           appState: appState, entry: entry
                       ) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("提交后先进入待审批，在枢纽批准了才会真正删除（聊天页点顶部胶囊打开）；驳回则保持原样。")
        }
    }

    @ViewBuilder
    private func content(_ entry: BridgeMemoryEntry) -> some View {
        let pending = store.hasPendingOperation(entry)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                metaGroup(entry)
                contentGroup(entry)
                if pending {
                    Text("这条记忆有一条修改正在待审批，批准前内容保持原样。")
                        .font(.footnote)
                        .foregroundStyle(Palette.primary)
                        .padding(.bottom, OneDayMetrics.spacingM)
                }
                if let note = store.notesOnDelete {
                    InlineError(note)
                        .padding(.bottom, OneDayMetrics.spacingM)
                }
                actionsGroup(entry, pending: pending)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
    }

    private func metaGroup(_ entry: BridgeMemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                LabeledContent("来源", value: entry.target.label)
                GroupDivider()
                LabeledContent(
                    "更新时间",
                    value: AdminFormat.short(
                        Date(timeIntervalSince1970: entry.updatedAt)
                    )
                )
            }
            .odGroup()
            Text("更新时间是记忆文件的最近修改时刻，同一文件里的条目相同。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)
        }
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private func contentGroup(_ entry: BridgeMemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("全文")
                .padding(.bottom, OneDayMetrics.spacingS)
            Group {
                if let detail = store.details[entryID] {
                    Text(detail.content)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let error = store.detailErrors[entryID] {
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                        InlineError(error)
                        Button("重试") {
                            Task {
                                await store.loadDetail(
                                    appState: appState, id: entryID
                                )
                            }
                        }
                        .buttonStyle(.odSecondary)
                    }
                } else {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        ProgressView()
                        Text("正在读取全文…")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .padding(OneDayMetrics.spacingM)
            .odGroup()
        }
        .padding(.bottom, 28)
    }

    private func actionsGroup(
        _ entry: BridgeMemoryEntry, pending: Bool
    ) -> some View {
        let writable = !pending && store.memoryGateEnabled != false
        return VStack(spacing: OneDayMetrics.spacingS) {
            Button {
                showingEditor = true
            } label: {
                Label("编辑这条记忆", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.odSecondary)
            .disabled(!writable || store.details[entryID] == nil)
            Button(role: .destructive) {
                store.clearDeleteNote()
                confirmingForget = true
            } label: {
                Label("遗忘这条记忆", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.odSecondary)
            .disabled(!writable)
            if store.memoryGateEnabled == false {
                Text("记忆写入审批未启用，暂时不能提交修改或遗忘。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }
}

/// 记忆编辑器（新建/编辑共用）：字段件口径——新建
/// 选目标（长期记忆/用户档案），编辑目标只读；正文
/// TextEditor 全量编辑。提交只发起 propose：成功
/// 即关表单、回列表看「待审批」状态，绝不在本地
/// 把条目改成新内容冒充已生效。
struct MemoryEntryEditorView: View {
    enum Mode {
        case create
        case edit(entry: BridgeMemoryEntry, currentContent: String)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: MemoriesStore
    let mode: Mode

    @State private var target: MemoryTarget = .memory
    @State private var content: String = ""

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var validationProblem: String? {
        switch mode {
        case .create:
            return MemoryProposalValidation.problem(
                operation: .create, content: content
            )
        case .edit(_, let currentContent):
            return MemoryProposalValidation.problem(
                operation: .update, content: content,
                originalContent: currentContent
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    targetGroup
                    contentGroup
                    if let error = store.proposeError {
                        InlineError(error)
                            .padding(.bottom, OneDayMetrics.spacingM)
                    }
                    Button(store.proposing ? "提交中…" : "提交待审批") {
                        Task { await submit() }
                    }
                    .buttonStyle(.odPrimary)
                    .disabled(
                        store.proposing || validationProblem != nil
                    )
                    Text("提交后先进入待审批，在枢纽批准了才会真正生效（聊天页点顶部胶囊打开）；驳回则保持原样。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingS)
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle(isEdit ? "编辑记忆" : "新建记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if case .edit(let entry, let currentContent) = mode {
                    target = entry.target
                    if content.isEmpty { content = currentContent }
                }
            }
        }
    }

    @ViewBuilder
    private var targetGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("记到哪里")
                .padding(.bottom, OneDayMetrics.spacingS)
            if isEdit {
                HStack {
                    Text(target.label)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("目标文件不能改")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .odGroup()
            } else {
                Picker("记到哪里", selection: $target) {
                    Text("长期记忆").tag(MemoryTarget.memory)
                    Text("用户档案").tag(MemoryTarget.user)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.bottom, 28)
    }

    private var contentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("内容")
                .padding(.bottom, OneDayMetrics.spacingS)
            TextEditor(text: $content)
                .frame(minHeight: 180)
                .padding(OneDayMetrics.spacingS)
                .odGroup()
            if let problem = validationProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingS)
            }
        }
        .padding(.bottom, 28)
    }

    private func submit() async {
        store.clearProposeError()
        let ok: Bool
        switch mode {
        case .create:
            ok = await store.proposeCreate(
                appState: appState, target: target, content: content
            )
        case .edit(let entry, let currentContent):
            ok = await store.proposeUpdate(
                appState: appState, entry: entry,
                currentContent: currentContent, newContent: content
            )
        }
        if ok { dismiss() }
    }
}
