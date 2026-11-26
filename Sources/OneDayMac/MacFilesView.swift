import SwiftUI
import OneDayCore

/// 文件库列表（棒 3，对位 #5/#37）：聚合读面单流消
/// 费；置顶段在前（本机账）、打开历史在后；顶部过
/// 滤按名/路径子串（与全局搜索文件段同判据）。
struct MacFilesView: View {
    @Environment(SessionStore.self) private var session
    var store: MacFilesStore
    @Binding var selection: String?
    @State private var filter = ""

    private var visible: [FileLibraryItem] {
        let needle = filter
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return store.items }
        return store.items.filter {
            $0.entry.name.lowercased().contains(needle)
                || $0.entry.path.lowercased().contains(needle)
        }
    }

    var body: some View {
        Group {
            if let error = store.loadError, store.items.isEmpty {
                ContentUnavailableView {
                    Label("文件库加载失败", systemImage: "folder")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await store.refresh(session: session) }
                    }
                }
            } else if store.loaded && store.items.isEmpty {
                ContentUnavailableView(
                    "文件库是空的",
                    systemImage: "folder",
                    description: Text("产出文件会出现在这里。")
                )
            } else {
                List(selection: $selection) {
                    let pinned = visible.filter {
                        store.isPinned($0.entry.path)
                    }
                    if !pinned.isEmpty {
                        Section("置顶") {
                            ForEach(pinned, id: \.entry.path) {
                                row($0).tag($0.entry.path)
                            }
                        }
                    }
                    Section("全部文件（\(visible.count)）") {
                        ForEach(visible, id: \.entry.path) {
                            row($0).tag($0.entry.path)
                        }
                    }
                    if !store.history.isEmpty && filter.isEmpty {
                        Section("打开历史") {
                            ForEach(store.history) { record in
                                Button {
                                    selection = record.path
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(
                                            systemName: "clock.arrow.circlepath"
                                        )
                                        .foregroundStyle(.secondary)
                                        Text(record.name)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(
                                            MacTimeText.short(record.at)
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.refresh(session: session) }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            TextField("按文件名或路径过滤", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .task {
            if !store.loaded {
                await store.refresh(session: session)
            }
        }
    }

    private func row(_ item: FileLibraryItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: Self.icon(for: item.entry))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let size = item.entry.size {
                        Text(FileSizeText.compact(size))
                    }
                    if let mtime = item.entry.mtime {
                        Text(MacTimeText.short(mtime))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isPinned(item.entry.path) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    static func icon(for entry: WorkspaceFileEntry) -> String {
        if entry.isDirectory { return "folder" }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg":
            return "photo"
        case "pdf": return "doc.richtext"
        case "md", "txt", "rtf": return "doc.text"
        case "zip", "tar", "gz", "7z": return "archivebox"
        case "mp3", "wav", "m4a": return "waveform"
        case "mp4", "mov": return "film"
        case "html", "htm": return "globe"
        default: return "doc"
        }
    }
}
