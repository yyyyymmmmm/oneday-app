import SwiftUI
import OneDayCore
import OneDayDesign

/// 会话列表（棒 1，对位 #9，中栏）：真实会话行
/// （标题/模型/时间/未读徽标/置顶标），搜索过滤，
/// 右键菜单全动作（置顶/改名/归档/删除），⌘F 聚焦
/// 搜索、⌘⌫ 删选中、段切换看归档。写动作全走列表
/// 店的服务端围栏口径，落定回读刷新。
struct MacSessionListView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var listStore: MacSessionListStore
    @Binding var selectedSessionID: String?
    var onSelect: (ServerSession) -> Void
    var onNew: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var renameTarget: ServerSession?
    @State private var renameText = ""
    @State private var deleteTarget: ServerSession?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = listStore.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            list
        }
        .background(Palette.pageBG)
        .task {
            await listStore.load(from: session)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索会话", text: $listStore.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !listStore.searchText.isEmpty {
                    Button {
                        listStore.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Palette.fieldFill,
                in: RoundedRectangle(cornerRadius: 8)
            )
            // ⌘F 聚焦搜索（隐藏钮承快捷键）
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
            Button {
                listStore.showArchived.toggle()
            } label: {
                Image(
                    systemName: listStore.showArchived
                        ? "tray.full" : "archivebox"
                )
            }
            .help(listStore.showArchived ? "看未归档" : "看已归档")
            Button {
                Task { await listStore.load(from: session) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新")
            Button(action: onNew) {
                Image(systemName: "square.and.pencil")
            }
            .help("新对话")
        }
        .padding(10)
    }

    private var list: some View {
        List(
            listStore.visibleSessions,
            selection: $selectedSessionID
        ) { item in
            row(item)
                .tag(item.id)
                .contextMenu { contextMenu(for: item) }
        }
        .listStyle(.inset)
        .overlay {
            if listStore.visibleSessions.isEmpty {
                ContentUnavailableView(
                    listStore.isLoading ? "正在加载…" : "暂无会话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(
                        listStore.showArchived
                            ? "没有已归档的会话。"
                            : "点右上角新建对话。"
                    )
                )
            }
        }
        .onDeleteCommand {
            if let id = selectedSessionID,
               let target = listStore.visibleSessions
                   .first(where: { $0.id == id }) {
                deleteTarget = target
            }
        }
        .alert(
            "改名",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("标题", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    listStore.rename(
                        target, title: renameText, from: session
                    )
                }
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "删除这个会话？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("删除", role: .destructive) {
                listStore.delete(target, from: session)
                if selectedSessionID == target.id {
                    selectedSessionID = nil
                }
                deleteTarget = nil
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: { target in
            Text("「\(MacSessionListStore.titleText(for: target))」将从服务端删除，不可恢复。")
        }
    }

    private func row(_ item: ServerSession) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if item.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(MacSessionListStore.titleText(for: item))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let model = item.model {
                        Text(model)
                            .lineLimit(1)
                    }
                    if let date = item.startedDate {
                        Text(date, format: .relative(presentation: .named))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            let unread = listStore.unreadCount(for: item)
            if unread > 0 {
                Text("\(unread)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Palette.primary, in: Capsule()
                    )
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func contextMenu(for item: ServerSession) -> some View {
        Button {
            listStore.togglePin(item, from: session)
        } label: {
            Label(
                item.isPinned == true ? "取消置顶" : "置顶",
                systemImage: item.isPinned == true
                    ? "pin.slash" : "pin"
            )
        }
        Button {
            renameText = MacSessionListStore.titleText(for: item)
            renameTarget = item
        } label: {
            Label("改名", systemImage: "pencil")
        }
        Button {
            listStore.setArchived(
                item, archived: !(item.isArchived == true),
                from: session
            )
        } label: {
            Label(
                item.isArchived == true ? "取消归档" : "归档",
                systemImage: item.isArchived == true
                    ? "tray.and.arrow.up" : "archivebox"
            )
        }
        Divider()
        Button(role: .destructive) {
            deleteTarget = item
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
}
