import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 宿主机实时 PTY 终端（Hermes v0.23.0 `WS /api/pty`）：
/// 直连 Hermes 宿主机 POSIX PTY WebSocket，支持实时交互式 CLI、
/// 快捷控制键（Ctrl+C / Tab / Esc / Clear）、断线重连与清屏。
struct HostPTYTerminalView: View {
    @Environment(AppState.self) private var appState

    @State private var outputBuffer = ""
    @State private var commandInput = ""
    @State private var connectionState: PTYConnectionState = .disconnected
    @State private var statusBanner: String?
    @State private var socketTask: URLSessionWebSocketTask?
    @State private var receiveTask: Task<Void, Never>?
    @State private var startFresh = false

    private enum PTYConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "未连接"
            case .connecting: return "连接中"
            case .connected: return "已连接"
            case .failed: return "连接异常"
            }
        }

        var tone: SettingsStatusTone {
            switch self {
            case .disconnected: return .neutral
            case .connecting: return .warning
            case .connected: return .healthy
            case .failed: return .error
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            terminalCanvas
            quickKeyBar
            inputComposer
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .navigationTitle("宿主机实时终端")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    outputBuffer = ""
                    Haptics.selection()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("清空终端输出")

                Button {
                    if connectionState == .connected {
                        disconnect()
                    } else {
                        connect()
                    }
                } label: {
                    Image(systemName: connectionState == .connected ? "bolt.slash.fill" : "bolt.fill")
                }
                .accessibilityLabel(connectionState == .connected ? "断开终端" : "重连终端")
            }
        }
        .onAppear {
            if connectionState == .disconnected {
                connect()
            }
        }
        .onDisappear {
            disconnect()
        }
    }

    private var headerBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            SettingsStatusPill(text: connectionState.label, tone: connectionState.tone)
            if let host = appState.config?.host {
                Text(host)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer()
            Toggle("新会话", isOn: $startFresh)
                .labelsHidden()
                .tint(Palette.primary)
            Text("新会话")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
    }

    private var terminalCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let statusBanner {
                        Text(statusBanner)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.orange)
                            .padding(.bottom, 4)
                    }
                    if outputBuffer.isEmpty {
                        Text(connectionState == .connecting
                             ? "正在连接 Hermes 宿主机 PTY (WS /api/pty)…"
                             : "终端输出将实时显示在此处。可输入命令或点击下方快捷控制键。")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.45))
                    } else {
                        Text(outputBuffer)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(Color(red: 0.86, green: 0.93, blue: 0.89))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("pty-bottom-anchor")
                }
                .padding(12)
            }
            .onChange(of: outputBuffer) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("pty-bottom-anchor", anchor: .bottom)
                }
            }
        }
    }

    private var quickKeyBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickKeyButton("Ctrl+C") { sendRaw("\u{03}") }
                quickKeyButton("Ctrl+D") { sendRaw("\u{04}") }
                quickKeyButton("Tab") { sendRaw("\t") }
                quickKeyButton("Esc") { sendRaw("\u{1B}") }
                quickKeyButton("Enter") { sendRaw("\r") }
                quickKeyButton("ls -la") { sendRaw("ls -la\r") }
                quickKeyButton("pwd") { sendRaw("pwd\r") }
                quickKeyButton("重连") { connect() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.42))
    }

    private func quickKeyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var inputComposer: some View {
        HStack(spacing: 8) {
            TextField("输入命令并发送…", text: $commandInput)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit {
                    submitCommand()
                }

            Button {
                submitCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(connectionState == .connected ? Palette.primary : Color.gray)
            }
            .disabled(connectionState != .connected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55))
    }

    private func connect() {
        disconnect()
        guard let config = appState.config else {
            connectionState = .failed("未连接服务器")
            statusBanner = "请先连接到 Hermes 服务器。"
            return
        }
        guard let wsURL = buildPTYWebSocketURL(config: config) else {
            connectionState = .failed("地址无效")
            statusBanner = "无法构造 WS /api/pty 地址。"
            return
        }

        connectionState = .connecting
        statusBanner = nil

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 30
        if let apiKey = appState.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let task = OneDayNetworkTransport.shared.standardSession.webSocketTask(with: request)
        socketTask = task
        task.resume()
        connectionState = .connected

        receiveTask = Task {
            await listenLoop(task: task)
        }
    }

    private func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        if connectionState != .disconnected {
            connectionState = .disconnected
        }
    }

    private func buildPTYWebSocketURL(config: ServerConfig) -> URL? {
        let httpURL = config.endpoint("/api/pty")
        guard var comps = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        var items: [URLQueryItem] = []
        if startFresh {
            items.append(URLQueryItem(name: "fresh", value: "1"))
        }
        if !items.isEmpty {
            comps.queryItems = items
        }
        return comps.url
    }

    private func listenLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                await MainActor.run {
                    switch message {
                    case .string(let text):
                        appendOutput(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            appendOutput(text)
                        }
                    @unknown default:
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        connectionState = .failed(error.localizedDescription)
                        statusBanner = "PTY 连接已断开：\(error.localizedDescription)"
                    }
                }
                break
            }
        }
    }

    private func submitCommand() {
        let text = commandInput
        commandInput = ""
        sendRaw(text + "\r")
    }

    private func sendRaw(_ text: String) {
        guard let task = socketTask else { return }
        task.send(.string(text)) { error in
            if let error {
                Task { @MainActor in
                    statusBanner = "发送失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func appendOutput(_ raw: String) {
        // 过滤控制 JSON 帧（如 {"type":"resume","id":...}）并清理常见 ANSI 颜色转义序列
        if raw.hasPrefix("{\"type\":\"resume\"") { return }
        let cleaned = stripANSI(raw)
        outputBuffer.append(cleaned)
        if outputBuffer.count > 24_000 {
            outputBuffer = String(outputBuffer.suffix(20_000))
        }
    }

    private func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}
