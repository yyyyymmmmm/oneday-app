import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 原生多行输入框（棒 1，对位 #15）：NSTextView 系
/// （macOS 原生文本系统：拼写/替换/服务菜单全原生），
/// Return 发送、⇧Return 换行（Telegram Mac 口径）；
/// 粘贴图片/文件经回调进附件队列，不把图片塞进文本。
struct MacComposerView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void
    var onPasteAttachments: (_ items: [(fileName: String, data: Data)]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = MacComposerTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacComposerView
        weak var textView: NSTextView?

        init(_ parent: MacComposerView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        /// Return（无修饰）＝发送；⇧Return 走默认换行
        func textView(
            _ textView: NSTextView, doCommandBy selector: Selector
        ) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?
                    .modifierFlags ?? []
                if flags.contains(.shift) {
                    return false
                }
                parent.onSend()
                return true
            }
            return false
        }

        func handlePaste() -> Bool {
            let pasteboard = NSPasteboard.general
            var items: [(fileName: String, data: Data)] = []
            if let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] {
                for url in urls {
                    if let data = try? Data(contentsOf: url) {
                        items.append(
                            (fileName: url.lastPathComponent, data: data)
                        )
                    }
                }
            }
            if items.isEmpty,
               let image = NSImage(pasteboard: pasteboard),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(
                   using: .png, properties: [:]
               ) {
                items.append((fileName: "粘贴图片.png", data: png))
            }
            guard !items.isEmpty else { return false }
            parent.onPasteAttachments(items)
            return true
        }
    }
}

/// 拦截粘贴的 NSTextView：剪贴板里有文件/图片时走
/// 附件回调（回调消费了才拦截，纯文本粘贴照旧）
final class MacComposerTextView: NSTextView {
    weak var coordinator: MacComposerView.Coordinator?

    override func paste(_ sender: Any?) {
        if coordinator?.handlePaste() == true { return }
        super.paste(sender)
    }
}

/// 拖拽/选择文件的统一读取（聊天面 .onDrop 与
/// NSOpenPanel 共用）：文件 URL → （文件名, 字节）
enum MacFileIntake {
    static func readProviders(
        _ providers: [NSItemProvider],
        completion: @escaping ([(fileName: String, data: Data)]) -> Void
    ) {
        var results: [(fileName: String, data: Data)] = []
        let group = DispatchGroup()
        for provider in providers
        where provider.hasItemConformingToTypeIdentifier(
            UTType.fileURL.identifier
        ) {
            group.enter()
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier
            ) { data, _ in
                defer { group.leave() }
                guard let data,
                      let url = URL(
                          dataRepresentation: data,
                          relativeTo: nil
                      ),
                      let bytes = try? Data(contentsOf: url)
                else { return }
                results.append(
                    (fileName: url.lastPathComponent, data: bytes)
                )
            }
        }
        group.notify(queue: .main) { completion(results) }
    }

    static func pickFiles() -> [(fileName: String, data: Data)] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else {
                return nil
            }
            return (fileName: url.lastPathComponent, data: data)
        }
    }
}
