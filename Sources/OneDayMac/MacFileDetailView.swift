import SwiftUI
import AppKit
import PDFKit
import OneDayCore

/// 文件详情（棒 3，对位 #37/#38）：字节经网关下载
/// 落本机缓存，预览按类型原生呈现（图/文本/PDF/
/// 其他）；动作全集＝打开（系统默认应用）/导出
/// （NSSavePanel）/置顶（本机账）；下载或预览失败
/// 走兜底面（原因＋重试，与 iOS 失败兜底同构）。
struct MacFileDetailView: View {
    @Environment(SessionStore.self) private var session
    var store: MacFilesStore
    let path: String?

    @State private var localURL: URL?
    @State private var loading = false
    @State private var failure: String?
    @State private var textContent: String?

    private var item: FileLibraryItem? {
        guard let path else { return nil }
        return store.items.first { $0.entry.path == path }
    }

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    actionBar(item)
                    Divider()
                    previewArea(item)
                }
            } else {
                ContentUnavailableView(
                    "选择一个文件",
                    systemImage: "folder",
                    description: Text("在中间列表点开一个，这里预览。")
                )
            }
        }
        .task(id: path) {
            await load()
        }
    }

    // MARK: - 动作条

    private func actionBar(_ item: FileLibraryItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.entry.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let size = item.entry.size {
                        Text(FileSizeText.compact(size))
                    }
                    if let mtime = item.entry.mtime {
                        Text(MacTimeText.full(mtime))
                    }
                    Text(item.entry.path)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.togglePin(item.entry.path)
            } label: {
                Label(
                    store.isPinned(item.entry.path)
                        ? "取消置顶" : "置顶",
                    systemImage: store.isPinned(item.entry.path)
                        ? "pin.slash" : "pin"
                )
            }
            Button {
                export(item)
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(localURL == nil)
            Button {
                openWithSystem(item)
            } label: {
                Label("打开", systemImage: "arrow.up.forward.app")
            }
            .disabled(localURL == nil)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 预览区（失败走兜底面，#38）

    @ViewBuilder
    private func previewArea(_ item: FileLibraryItem) -> some View {
        if loading {
            ProgressView("正在取文件…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let failure {
            ContentUnavailableView {
                Label("这个文件没打开", systemImage: "doc.badge.gearshape")
            } description: {
                Text(failure)
            } actions: {
                Button("重试") {
                    Task { await load(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let localURL {
            preview(for: item, url: localURL)
        } else {
            ContentUnavailableView(
                "还没有取到文件",
                systemImage: "doc",
                description: Text("稍等片刻，或点重试。")
            )
        }
    }

    @ViewBuilder
    private func preview(
        for item: FileLibraryItem, url: URL
    ) -> some View {
        let ext = (item.entry.name as NSString)
            .pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"]
            .contains(ext),
           let image = NSImage(contentsOf: url) {
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
        } else if ext == "pdf" {
            MacPDFPreview(url: url)
        } else if let textContent {
            ScrollView {
                Text(textContent)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            ContentUnavailableView {
                Label(
                    "此类型暂不在 App 内预览",
                    systemImage: MacFilesView.icon(for: item.entry)
                )
            } description: {
                Text("可以用「打开」交给系统默认应用，或「导出」存到本地。")
            }
        }
    }

    // MARK: - 动作实现

    private func load(force: Bool = false) async {
        guard let item else {
            localURL = nil
            return
        }
        if force, let existing = localURL {
            try? FileManager.default.removeItem(at: existing)
            localURL = nil
        }
        loading = true
        failure = nil
        textContent = nil
        defer { loading = false }
        do {
            let url = try await store.localCopy(
                session: session, item: item
            )
            localURL = url
            let ext = (item.entry.name as NSString)
                .pathExtension.lowercased()
            let textExts: Set<String> = [
                "txt", "md", "json", "swift", "csv", "log",
                "xml", "yml", "yaml", "html", "htm", "sh", "py",
            ]
            if textExts.contains(ext) {
                textContent = try? String(
                    contentsOf: url, encoding: .utf8
                )
            }
        } catch let error as HermesError {
            failure = error.userMessage
        } catch {
            failure = "取文件失败：\(error.localizedDescription)"
        }
    }

    private func openWithSystem(_ item: FileLibraryItem) {
        guard let localURL else { return }
        store.recordOpen(item)
        NSWorkspace.shared.open(localURL)
    }

    private func export(_ item: FileLibraryItem) {
        guard let localURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.entry.name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let target = panel.url {
            do {
                if FileManager.default.fileExists(
                    atPath: target.path
                ) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(
                    at: localURL, to: target
                )
                store.recordOpen(item)
            } catch {
                store.actionNote =
                    "导出失败：\(error.localizedDescription)"
            }
        }
    }
}

/// PDF 预览（PDFKit 原生）：与 Quick Look 同系的系
/// 统预览件
struct MacPDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}
