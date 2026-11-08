import AVKit
import OneDayCore
import OneDayDesign
import SwiftUI
import UIKit

/// 文件格（0.2.1 新增，仿 Muse 资源库）：顶部分段
/// 「文件／影音」。文件＝服务端工作区（GET /api/files，
/// 根被服务端 locked_root 锁在数据目录内）目录浏览＋预览、
/// 下载到本地、删除（带确认）；影音＝按 mime/扩展名过滤的
/// 图片/视频/音频，网格缩略图浏览、点开预览。
/// 数据口径全部来自 2026-11-08 生产实查回执（见
/// HermesFilesModels.swift 的结构注释）。
struct FilesView: View {
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("浏览方式", selection: $segment) {
                    Text("文件").tag(0)
                    Text("影音").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingS)
                if segment == 0 {
                    DirectoryListView(path: nil)
                } else {
                    MediaGridView()
                }
            }
            .background(Palette.pageBG)
            .navigationTitle("文件")
            .navigationDestination(for: String.self) { path in
                DirectoryListView(path: path)
                    .navigationTitle((path as NSString).lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(for: WorkspaceFileEntry.self) { entry in
                FilePreviewView(entry: entry)
            }
        }
    }
}

// MARK: - 目录列表

private struct DirectoryListView: View {
    @Environment(AppState.self) private var appState
    let path: String?

    @State private var listing: FilesListing?
    @State private var loadError: String?
    @State private var pendingDelete: WorkspaceFileEntry?
    @State private var shareItem: FileShareItem?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let listing {
                    if listing.entries.isEmpty {
                        EmptyState(
                            icon: "folder",
                            title: "这个文件夹是空的",
                            message: "服务端工作区里暂时没有内容。"
                        )
                        .padding(.top, OneDayMetrics.spacingXXL)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(listing.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    GroupDivider(inset: OneDayMetrics.dividerInset)
                                }
                                fileRow(entry)
                            }
                        }
                        .odGroup()
                    }
                    if let locked = listing.lockedRoot {
                        Text("工作区根目录：\(locked)（服务端锁定，无法越级浏览）")
                            .font(TypeScale.footnote)
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                } else if let loadError {
                    EmptyState(
                        icon: "exclamationmark.triangle",
                        title: "读取失败",
                        message: loadError
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, OneDayMetrics.spacingXXL)
                }
                if let notice {
                    Text(notice)
                        .font(TypeScale.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingS)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "删除「\(pendingDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDelete {
                    Task { await delete(entry) }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.isDirectory == true
                 ? "将递归删除该文件夹及其全部内容，无法恢复。"
                 : "删除后无法恢复。")
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
    }

    @ViewBuilder
    private func fileRow(_ entry: WorkspaceFileEntry) -> some View {
        if entry.isDirectory {
            NavigationLink(value: entry.path) {
                rowContent(entry, chevron: true)
            }
            .buttonStyle(.plain)
            .contextMenu { rowMenu(entry) }
        } else {
            NavigationLink(value: entry) {
                rowContent(entry, chevron: true)
            }
            .buttonStyle(.plain)
            .contextMenu { rowMenu(entry) }
        }
    }

    private func rowContent(_ entry: WorkspaceFileEntry, chevron: Bool) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: entry.odIconName)
                .font(TypeScale.body)
                .foregroundStyle(entry.isDirectory ? Palette.primary : Palette.inkSecondary)
                .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(entry.odSubtitle)
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowMenu(_ entry: WorkspaceFileEntry) -> some View {
        if !entry.isDirectory {
            Button {
                Task { await download(entry) }
            } label: {
                Label("下载到本地", systemImage: "arrow.down.to.line")
            }
        }
        Button(role: .destructive) {
            pendingDelete = entry
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func load() async {
        do {
            listing = try await appState.performAdmin { client, config in
                try await client.files(config: config, path: path)
            }
            loadError = nil
        } catch {
            loadError = (error as? HermesError)?.userMessage ?? "读取文件列表失败。"
        }
    }

    private func delete(_ entry: WorkspaceFileEntry) async {
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteFile(
                    config: config, path: entry.path, recursive: entry.isDirectory
                )
            }
            notice = "已删除「\(entry.name)」。"
            await load()
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }

    private func download(_ entry: WorkspaceFileEntry) async {
        do {
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(config: config, path: entry.path)
            }
            shareItem = try FileShareItem.write(data: data, name: entry.name)
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "下载失败，请稍后再试。"
        }
    }
}

// MARK: - 影音网格

private struct MediaGridView: View {
    @Environment(AppState.self) private var appState
    @State private var media: [WorkspaceFileEntry]?
    @State private var loadError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        ScrollView {
            if let media {
                if media.isEmpty {
                    EmptyState(
                        icon: "photo.on.rectangle.angled",
                        title: "暂无影音文件",
                        message: "工作区里还没有图片、视频或音频文件。"
                    )
                    .padding(.top, OneDayMetrics.spacingXXL)
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(media) { entry in
                            NavigationLink(value: entry) {
                                MediaCell(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if let loadError {
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "读取失败",
                    message: loadError
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, OneDayMetrics.spacingXXL)
            }
        }
        .background(Palette.pageBG)
        .task { await collect() }
    }

    /// 从根递归收集影音（深度 ≤3、条目上限保护，避免大树全量遍历）
    private func collect() async {
        var found: [WorkspaceFileEntry] = []
        var queue: [(path: String?, depth: Int)] = [(nil, 0)]
        var visited = 0
        while !queue.isEmpty {
            let (path, depth) = queue.removeFirst()
            guard let listing = try? await appState.performAdmin({ client, config in
                try await client.files(config: config, path: path)
            }) else { continue }
            visited += listing.entries.count
            for entry in listing.entries {
                if entry.isDirectory {
                    if depth < 3 {
                        queue.append((entry.path, depth + 1))
                    }
                } else if entry.mediaKind != nil {
                    found.append(entry)
                }
            }
            if found.count >= 300 || visited >= 1500 { break }
        }
        media = found.sorted { ($0.mtime ?? 0) > ($1.mtime ?? 0) }
    }
}

private struct MediaCell: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Palette.fieldFill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: OneDayMetrics.spacingXS) {
                    Image(systemName: entry.odIconName)
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.inkSecondary)
                    Text(entry.name)
                        .font(TypeScale.monoCaption)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                        .padding(.horizontal, OneDayMetrics.spacingXS)
                }
            }
            if entry.mediaKind == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Palette.ink.opacity(0.55))
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .contentShape(Rectangle())
        .task(id: entry.path) {
            guard entry.mediaKind == .image else { return }
            // 缩略图走与预览相同的下载通道（客户端带会话 cookie）
            if let data = try? await appState.performAdmin({ client, config in
                try await client.fileData(config: config, path: entry.path)
            }) {
                image = UIImage(data: data)
            }
        }
    }
}

// MARK: - 预览

private struct FilePreviewView: View {
    @Environment(AppState.self) private var appState
    let entry: WorkspaceFileEntry

    @State private var image: UIImage?
    @State private var text: String?
    @State private var player: AVPlayer?
    @State private var loadError: String?
    @State private var shareItem: FileShareItem?
    @State private var rawData: Data?

    var body: some View {
        Group {
            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(OneDayMetrics.spacingM)
                }
            } else if let text {
                ScrollView {
                    Text(text)
                        .font(entry.isTextLike ? TypeScale.monoFootnote : TypeScale.body)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(OneDayMetrics.pageGutter)
                }
            } else if let player {
                VideoPlayer(player: player)
            } else if let loadError {
                EmptyState(
                    icon: "exclamationmark.triangle",
                    title: "预览失败",
                    message: loadError
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else if rawData != nil {
                EmptyState(
                    icon: entry.odIconName,
                    title: entry.name,
                    message: "此类型暂不支持 App 内预览，可下载到本地后用其他应用打开。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let rawData {
                        shareItem = try? FileShareItem.write(data: rawData, name: entry.name)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(rawData == nil)
                .accessibilityLabel("下载到本地")
            }
        }
        .sheet(item: $shareItem) { item in
            FileShareSheet(url: item.url)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let data = try await appState.performAdmin { client, config in
                try await client.fileData(config: config, path: entry.path)
            }
            rawData = data
            switch entry.mediaKind {
            case .image:
                image = UIImage(data: data)
                if image == nil {
                    loadError = "图片数据无法解析。"
                }
            case .video, .audio:
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(entry.name)
                try data.write(to: url)
                player = AVPlayer(url: url)
            case nil:
                if entry.isTextLike, let string = String(data: data, encoding: .utf8) {
                    text = string
                }
            }
        } catch {
            loadError = (error as? HermesError)?.userMessage ?? "读取文件失败。"
        }
    }
}

// MARK: - 共享小件

extension WorkspaceFileEntry {
    var odIconName: String {
        if isDirectory { return "folder" }
        switch mediaKind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case nil:
            return isTextLike ? "doc.text" : "doc"
        }
    }

    var odSubtitle: String {
        if isDirectory {
            return "文件夹"
        }
        let size = size.map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        let date = AdminFormat.short(modifiedAt)
        return [size, date].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct FileShareItem: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(data: Data, name: String) throws -> FileShareItem {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return FileShareItem(url: url)
    }
}

private struct FileShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
