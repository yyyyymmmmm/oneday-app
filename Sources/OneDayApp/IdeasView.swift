import OneDayCore
import OneDayDesign
import SwiftUI

/// 点子格（0.11.0 P5 转正）：oneday-bridge 点子仓真
/// 列表——卡＝标题＋详情＋关联目标 chip（解析得到才
/// 显示）＋已转任务标记；一键转任务经 P3 kanban 适配
/// 层落板（板未开通如实提示、不假成功）；删除走确认。
/// 桥未连接/未开通与目标格同口径、零假数据。
struct IdeasView: View {
    @Environment(AppState.self) private var appState
    @State private var store = IdeasStore()
    @State private var kanban = KanbanStore()
    @State private var showCreate = false
    @State private var deleteCandidate: BridgeIdea?

    var body: some View {
        NavigationStack {
            Group {
                switch store.loadState {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .notConnected(let message):
                    ContentUnavailableView {
                        Label("数据桥未连接", systemImage: "link.badge.plus")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重新检查") {
                            Task { await store.load(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("点子读取失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("重试") {
                            Task { await store.load(appState: appState) }
                        }
                        .buttonStyle(.bordered)
                    }
                case .ready:
                    readyContent
                }
            }
            .background(Palette.pageBG)
            .navigationTitle("点子")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreate = true
                    } label: {
                        Label("新建点子", systemImage: "plus")
                    }
                }
            }
            .task {
                await store.load(appState: appState)
            }
            .sheet(isPresented: $showCreate) {
                IdeaCreateView(store: store)
            }
            .confirmationDialog(
                "删除这个点子？",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible,
                presenting: deleteCandidate
            ) { idea in
                Button("删除点子", role: .destructive) {
                    Task { await store.delete(appState: appState, idea: idea) }
                }
                Button("取消", role: .cancel) {}
            } message: { _ in
                Text("只删点子本身；已经转成的任务不会受影响。")
            }
        }
    }

    @ViewBuilder
    private var readyContent: some View {
        if store.ideas.isEmpty {
            ContentUnavailableView(
                "暂无点子",
                systemImage: "lightbulb",
                description: Text("点右上角＋记下第一个点子")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: OneDayMetrics.spacingSM) {
                    ForEach(store.ideas) { idea in
                        IdeaCardView(
                            idea: idea,
                            goalTitle: store.goalTitle(for: idea),
                            converted: store.isConverted(idea),
                            acting: store.actingIDs.contains(idea.id),
                            note: store.notes[idea.id],
                            onConvert: {
                                Task {
                                    await store.convertToTask(
                                        appState: appState, idea: idea,
                                        kanban: kanban
                                    )
                                }
                            },
                            onDelete: { deleteCandidate = idea }
                        )
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            }
            .refreshable {
                await store.load(appState: appState)
            }
        }
    }
}

/// 点子卡（设计标准 §7 P5 锚：卡骨架＋关联 chip＋动作
/// 钮组）：已转任务后钮组收为标记＋删除，点子保留在列
struct IdeaCardView: View {
    let idea: BridgeIdea
    let goalTitle: String?
    let converted: Bool
    let acting: Bool
    let note: String?
    var onConvert: () -> Void
    var onDelete: () -> Void

    private var createdText: String {
        Date(timeIntervalSince1970: idea.createdAt)
            .formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            Text(idea.title)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.bodyInk)
                .lineLimit(2)
            if !idea.detail.isEmpty {
                Text(idea.detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                if let goalTitle {
                    Label(goalTitle, systemImage: "target")
                        .font(.footnote)
                        .foregroundStyle(Palette.primary)
                        .padding(.horizontal, OneDayMetrics.spacingS)
                        .padding(.vertical, OneDayMetrics.spacingXS)
                        .background(
                            Palette.primaryPale,
                            in: Capsule()
                        )
                        .lineLimit(1)
                }
                if converted {
                    Label("已转任务", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 0)
                Text(createdText)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                if !converted {
                    Button {
                        onConvert()
                    } label: {
                        Label(
                            acting ? "处理中…" : "转成任务",
                            systemImage: "arrow.right.circle"
                        )
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(acting)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("删除", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(acting)
            }
            if let note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(OneDayMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner,
                style: .continuous
            )
        )
    }
}

/// 新建点子（sheet）：标题＋详情＋可挂目标（picker 只
/// 列现存目标——服务端对假 goalId 回 400，客户端不给
/// 选不存在的；目标列表是打开表单时 IdeasStore 已拉的
/// 一批，提交时服务端再校验、错误透人话）
struct IdeaCreateView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let store: IdeasStore

    @State private var title = ""
    @State private var detail = ""
    @State private var goalId: String?

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingL) {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("点子")
                            .padding(.bottom, OneDayMetrics.spacingS)
                        VStack(spacing: 0) {
                            FieldRow(label: "标题") {
                                TextField("一句话说清这个点子", text: $title)
                            }
                            GroupDivider(inset: OneDayMetrics.spacingM)
                            FieldRow(label: "详情") {
                                TextField("可选", text: $detail, axis: .vertical)
                                    .lineLimit(2...6)
                            }
                            GroupDivider(inset: OneDayMetrics.spacingM)
                            FieldRow(label: "关联目标") {
                                Picker("关联目标", selection: $goalId) {
                                    Text("不关联").tag(String?.none)
                                    ForEach(store.goals) { goal in
                                        Text(goal.title)
                                            .tag(String?.some(goal.id))
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                        .odGroup()
                    }
                    if let error = store.createError {
                        InlineError(error)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("新建点子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.creating ? "创建中…" : "创建") {
                        Task {
                            if await store.create(
                                appState: appState, title: title,
                                detail: detail, goalId: goalId
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!isValid || store.creating)
                }
            }
        }
    }
}
