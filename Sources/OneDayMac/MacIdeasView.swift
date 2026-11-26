import SwiftUI
import OneDayCore

/// 想法列表（棒 3，对位 #3/#35）：待阅在前、已处理
/// 在后两段；工具栏新建＋刷新；页脚呈生成管道账面
/// （上次/下次生成时刻，旧桥无账面时整段不出现）。
struct MacIdeasView: View {
    @Environment(SessionStore.self) private var session
    var store: MacIdeasStore
    @Binding var selection: String?
    @State private var showCreate = false
    @State private var newTitle = ""
    @State private var newDetail = ""

    var body: some View {
        Group {
            if let error = store.loadError, store.ideas.isEmpty {
                ContentUnavailableView {
                    Label("想法加载失败", systemImage: "lightbulb")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await store.refresh(session: session) }
                    }
                }
            } else if store.loaded && store.ideas.isEmpty {
                ContentUnavailableView(
                    "暂无想法",
                    systemImage: "lightbulb",
                    description: Text("生成的点子会出现在这里。")
                )
            } else {
                List(selection: $selection) {
                    if !store.pendingIdeas.isEmpty {
                        Section("待阅（\(store.pendingIdeas.count)）") {
                            ForEach(store.pendingIdeas) { idea in
                                row(idea).tag(idea.id)
                            }
                        }
                    }
                    if !store.settledIdeas.isEmpty {
                        Section("已处理") {
                            ForEach(store.settledIdeas) { idea in
                                row(idea).tag(idea.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { showCreate = true } label: {
                    Label("新建想法", systemImage: "plus")
                }
                Button {
                    Task { await store.refresh(session: session) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let generation = store.generation {
                Text(generationLine(generation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $showCreate) {
            createSheet
        }
        .task {
            if !store.loaded {
                await store.refresh(session: session)
            }
        }
    }

    private func row(_ idea: BridgeIdea) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(IdeaEmoji.resolve(emoji: idea.emoji))
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title)
                    .font(.body)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Self.statusLabel(idea.status))
                    if let label = Self.domainLabel(idea) {
                        Text(label)
                    }
                    Text(MacTimeText.short(idea.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var createSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建想法")
                .font(.headline)
            TextField("标题", text: $newTitle)
                .textFieldStyle(.roundedBorder)
            Text("详情（可选）")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $newDetail)
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            HStack {
                Spacer()
                Button("取消") { showCreate = false }
                    .keyboardShortcut(.cancelAction)
                Button("新建") {
                    let title = newTitle
                    let detail = newDetail
                    showCreate = false
                    newTitle = ""
                    newDetail = ""
                    Task {
                        _ = await store.create(
                            session: session, title: title,
                            detail: detail
                        )
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    newTitle.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                )
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    private func generationLine(
        _ info: BridgeGenerationInfo
    ) -> String {
        var parts: [String] = []
        if let last = info.lastRunAt {
            parts.append("上次生成 \(MacTimeText.short(last))")
        }
        if info.running {
            parts.append("正在生成")
        } else if let next = info.nextRunAt {
            parts.append("下次 \(MacTimeText.short(next))")
        }
        return parts.joined(separator: " · ")
    }

    static func statusLabel(_ status: IdeaStatus) -> String {
        switch status {
        case .pending: return "待阅"
        case .adopted: return "已采纳"
        case .dismissed: return "已忽略"
        case .expired: return "已过期"
        }
    }

    static func domainLabel(_ idea: BridgeIdea) -> String? {
        if let label = idea.categoryLabel, !label.isEmpty {
            return label
        }
        if let domain = idea.domain,
           let parsed = IdeaDomain(rawValue: domain) {
            return parsed.title
        }
        return idea.category
    }
}
