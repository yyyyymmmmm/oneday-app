import OneDayCore
import OneDayDesign
import SwiftUI
import WebKit

// MARK: - #31 预览窗批注与引导游览（iOS WKWebView 交互预览 + 落点批注回传）

struct PreviewAnnotationPin: Identifiable, Equatable {
    let id = UUID()
    let index: Int
    let xRatio: CGFloat
    let yRatio: CGFloat
    var note: String
}

struct PreviewTourTarget: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let urlString: String?
    let htmlContent: String?
}

struct InteractivePreviewAnnotationSheet: View {
    let targets: [PreviewTourTarget]
    let onSendAnnotations: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    enum InteractionMode: String, CaseIterable, Identifiable {
        case interact = "交互预览"
        case annotate = "落点批注"
        var id: String { rawValue }
    }

    @State private var currentIndex = 0
    @State private var mode: InteractionMode = .interact
    @State private var pins: [PreviewAnnotationPin] = []
    @State private var pendingPinCoord: (CGFloat, CGFloat)?
    @State private var pendingNote = ""
    @State private var customURLText = ""

    private var activeTarget: PreviewTourTarget {
        if targets.indices.contains(currentIndex) {
            return targets[currentIndex]
        }
        return PreviewTourTarget(
            title: "实时预览工作台",
            urlString: nil,
            htmlContent: """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>body{font-family:-apple-system,sans-serif;padding:24px;color:#1c1c1e;background:#f8f9fa}
            .card{background:#fff;border-radius:16px;padding:20px;box-shadow:0 4px 16px rgba(0,0,0,.06)}
            h2{margin-top:0}p{color:#636366;line-height:1.6}</style></head>
            <body><div class="card"><h2>OneDay 交互预览与批注</h2>
            <p>可在顶部输入预览地址，或直接预览对话中生成的 HTML/页面产物。切换到「落点批注」后点击画布任意位置添加修改批注，一键发回 Hermes 迭代。</p></div></body></html>
            """
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Picker("模式", selection: $mode) {
                        ForEach(InteractionMode.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if targets.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(targets.enumerated()), id: \.element.id) { idx, item in
                                    Button {
                                        Haptics.selection()
                                        currentIndex = idx
                                        pins = []
                                    } label: {
                                        Text("\(idx + 1). \(item.title)")
                                            .font(.caption.weight(currentIndex == idx ? .semibold : .regular))
                                            .foregroundStyle(currentIndex == idx ? Palette.primary : Palette.inkSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(currentIndex == idx ? Palette.primaryTint : Palette.surface, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                            TextField("输入要预览的 https:// 地址（可选）", text: $customURLText)
                                .font(.caption.monospaced())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.settingsBG)

                GeometryReader { geo in
                    ZStack {
                        PreviewWebView(
                            urlString: customURLText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("http")
                                ? customURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                                : activeTarget.urlString,
                            htmlContent: activeTarget.htmlContent
                        )
                        .allowsHitTesting(mode == .interact)

                        if mode == .annotate {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    let xr = max(0, min(1, location.x / max(geo.size.width, 1)))
                                    let yr = max(0, min(1, location.y / max(geo.size.height, 1)))
                                    pendingPinCoord = (xr, yr)
                                    pendingNote = ""
                                    Haptics.selection()
                                }
                        }

                        ForEach(pins) { pin in
                            ZStack {
                                Circle()
                                    .fill(Palette.primary)
                                    .frame(width: 24, height: 24)
                                    .shadow(radius: 3)
                                Text("\(pin.index)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                            .position(
                                x: pin.xRatio * geo.size.width,
                                y: pin.yRatio * geo.size.height
                            )
                        }
                    }
                }

                if !pins.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("已标记 \(pins.count) 处批注")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Button("清空") {
                                pins = []
                            }
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(pins) { pin in
                                    Text("#\(pin.index) \(pin.note)")
                                        .font(.caption)
                                        .foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Palette.fieldFill, in: Capsule())
                                }
                            }
                        }
                        Button {
                            let report = buildAnnotationPrompt()
                            Haptics.success()
                            dismiss()
                            onSendAnnotations(report)
                        } label: {
                            HStack {
                                Spacer()
                                Label("将 \(pins.count) 条批注发回 Hermes 修改", systemImage: "paperplane.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .background(Palette.primary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.odPressable)
                    }
                    .padding(12)
                    .background(Palette.surface)
                }
            }
            .navigationTitle(activeTarget.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("添加画布批注 #\(pins.count + 1)", isPresented: Binding(
                get: { pendingPinCoord != nil },
                set: { if !$0 { pendingPinCoord = nil } }
            )) {
                TextField("描述这里要修改什么（如：按钮间距放大）", text: $pendingNote)
                Button("添加") {
                    if let coord = pendingPinCoord {
                        let note = pendingNote.trimmingCharacters(in: .whitespacesAndNewlines)
                        pins.append(
                            PreviewAnnotationPin(
                                index: pins.count + 1,
                                xRatio: coord.0,
                                yRatio: coord.1,
                                note: note.isEmpty ? "调整此区域样式与排版" : note
                            )
                        )
                    }
                    pendingPinCoord = nil
                }
                Button("取消", role: .cancel) { pendingPinCoord = nil }
            }
        }
    }

    private func buildAnnotationPrompt() -> String {
        let lines = pins.map { pin in
            let xPct = Int((pin.xRatio * 100).rounded())
            let yPct = Int((pin.yRatio * 100).rounded())
            return "- 批注 #\(pin.index)（坐标 \(xPct)%, \(yPct)%）：\(pin.note)"
        }.joined(separator: "\n")
        return "请根据我在交互预览页「\(activeTarget.title)」上标记的批注进行修改：\n\(lines)"
    }
}

private struct PreviewWebView: UIViewRepresentable {
    let urlString: String?
    let htmlContent: String?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let urlString, let url = URL(string: urlString), webView.url != url {
            webView.load(URLRequest(url: url))
        } else if let htmlContent, urlString == nil {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}
