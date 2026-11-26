import SwiftUI
import OneDayCore

extension Notification.Name {
    /// ⌘K 全局搜索唤出（App 命令菜单 → 主窗呈现）
    static let macOpenGlobalSearch =
        Notification.Name("mac.openGlobalSearch")
    /// 在主窗打开指定会话（速记窗发送后跳转用）
    static let macOpenSession =
        Notification.Name("mac.openSession")
}

/// 全局搜索（棒 3，对位 #10）：⌘K 命令面板式——会
/// 话走服务端全文搜索（450ms 防抖，与 iOS 同口径）、
/// 文件走文件库本地过滤、设置走 Core 设置目录搜索；
/// 命中点击直达对应面。定时任务段待枢纽棒 Cron 面
/// 落地后补（iOS 有此段，Mac 暂无其数据源，不假装）。
struct MacSearchView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openSettings) private var openSettings
    var filesStore: MacFilesStore
    var onOpenSession: (String) -> Void
    var onOpenFile: (String) -> Void
    var onClose: () -> Void

    @State private var query = ""
    @State private var sessionHits: [SessionSearchHit] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fileHits: [FileLibraryItem] {
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.lowercased()
        return filesStore.items.filter {
            $0.entry.name.lowercased().contains(needle)
                || $0.entry.path.lowercased().contains(needle)
        }
    }

    private var settingHits: [SettingsCatalogEntry] {
        guard !trimmed.isEmpty else { return [] }
        return SettingsCatalog.search(trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    "搜索会话、文件、设置", text: $query
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onChange(of: query) { _, _ in scheduleSearch() }
                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            List {
                if !trimmed.isEmpty {
                    sessionSection
                    fileSection
                    settingSection
                    if !searching && sessionHits.isEmpty
                        && fileHits.isEmpty && settingHits.isEmpty {
                        Text("没有找到和「\(trimmed)」相关的东西。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 580, height: 460)
        .onAppear {
            fieldFocused = true
            Task {
                if !filesStore.loaded {
                    await filesStore.refresh(session: session)
                }
            }
        }
    }

    private var sessionSection: some View {
        Group {
            if !sessionHits.isEmpty {
                Section("会话") {
                    ForEach(sessionHits) { hit in
                        Button {
                            onOpenSession(hit.sessionID)
                        } label: {
                            VStack(
                                alignment: .leading, spacing: 2
                            ) {
                                Text(hit.displayTitle)
                                    .lineLimit(1)
                                if let snippet = hit.snippet,
                                   !snippet.isEmpty {
                                    Text(snippet)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if searching {
                Section("会话") {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在搜会话…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var fileSection: some View {
        Group {
            if !fileHits.isEmpty {
                Section("文件") {
                    ForEach(fileHits, id: \.entry.path) { item in
                        Button {
                            onOpenFile(item.entry.path)
                        } label: {
                            VStack(
                                alignment: .leading, spacing: 2
                            ) {
                                Text(item.entry.name)
                                    .lineLimit(1)
                                Text(item.entry.path)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var settingSection: some View {
        Group {
            if !settingHits.isEmpty {
                Section("设置") {
                    ForEach(settingHits) { entry in
                        Button {
                            openSettings()
                            onClose()
                        } label: {
                            VStack(
                                alignment: .leading, spacing: 2
                            ) {
                                Text(entry.title)
                                    .lineLimit(1)
                                Text(entry.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 450ms 防抖＋旧任务取消（与 iOS 全局搜索同口径）
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = trimmed
        guard !query.isEmpty else {
            sessionHits = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if Task.isCancelled { return }
            guard let config = session.config,
                  let key = session.apiKey else {
                searching = false
                return
            }
            let hits = try? await session.chatClient.searchSessions(
                config: config, apiKey: key, query: query,
                limit: 50
            )
            if Task.isCancelled { return }
            sessionHits = hits ?? []
            searching = false
        }
    }
}
