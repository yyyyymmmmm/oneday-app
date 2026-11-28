import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 宿主机进程快照条目（用于后台进程注册表与控制面板）
struct HostProcessEntry: Identifiable, Equatable {
    let pid: Int
    let cpu: String
    let mem: String
    let elapsed: String
    let command: String

    var id: Int { pid }
}

/// 宿主机实时 PTY 终端与后台进程注册表（Hermes v0.23.0 `WS /api/pty` + Process Registry）：
/// 顶部 Segmented 切换：
/// 1. 实时终端：直连 Hermes 宿主机 POSIX PTY WebSocket，支持交互式 CLI、快捷控制键与断线重连；
/// 2. 后台进程：实时拉取宿主机运行中进程列表，支持新建后台任务、查看输出与一键发送 SIGTERM / SIGKILL。
struct HostPTYTerminalView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: String, CaseIterable, Identifiable {
        case terminal = "实时终端"
        case processes = "后台进程"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .terminal
    @State private var outputBuffer = ""
    @State private var commandInput = ""
    @State private var connectionState: PTYConnectionState = .disconnected
    @State private var statusBanner: String?
    @State private var socketTask: URLSessionWebSocketTask?
    @State private var receiveTask: Task<Void, Never>?
    @State private var startFresh = false

    // 后台进程注册表状态
    @State private var processes: [HostProcessEntry] = []
    @State private var processSearch = ""
    @State private var isRefreshingProcesses = false
    @State private var capturingProcessList = false
    @State private var processCaptureBuffer = ""
    @State private var showLaunchBgSheet = false
    @State private var newBgCommand = ""
    @State private var processNotice: String?

    private static let psStartMarker = "__ONEDAY_PS_BEGIN__"
    private static let psEndMarker = "__ONEDAY_PS_END__"

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

    private var filteredProcesses: [HostProcessEntry] {
        let q = processSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return processes }
        return processes.filter {
            $0.command.lowercased().contains(q) || String($0.pid).contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            if mode == .terminal {
                headerBar
                terminalCanvas
                quickKeyBar
                inputComposer
            } else {
                processRegistryPanel
            }
        }
        .background(mode == .terminal ? terminalCanvasBG : Palette.settingsBG)
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: mode)
        .navigationTitle(mode == .terminal ? "宿主机实时终端" : "后台进程注册表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if mode == .terminal {
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
                } else {
                    Button {
                        refreshProcesses()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新进程列表")

                    Button {
                        newBgCommand = ""
                        showLaunchBgSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("启动后台任务")
                }
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
        .onChange(of: mode) { _, newMode in
            if newMode == .processes && processes.isEmpty && connectionState == .connected {
                refreshProcesses()
            }
        }
        .sheet(isPresented: $showLaunchBgSheet) {
            NavigationStack {
                Form {
                    Section("在宿主机后台启动任务") {
                        TextField("例如：python3 -m http.server 8080", text: $newBgCommand)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Text("任务将通过 `nohup ... > /tmp/oneday_bg.log 2>&1 &` 在宿主机后台持续运行，可在进程列表中随时停止或查看日志。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                .navigationTitle("新建后台进程")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showLaunchBgSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("启动") {
                            let cmd = newBgCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cmd.isEmpty else { return }
                            sendRaw("nohup \(cmd) > /tmp/oneday_bg.log 2>&1 & echo $!\r")
                            processNotice = "已下发后台任务：\(cmd)"
                            Haptics.success()
                            showLaunchBgSheet = false
                            Task {
                                try? await Task.sleep(for: .milliseconds(600))
                                refreshProcesses()
                            }
                        }
                        .disabled(newBgCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var modeBar: some View {
        Picker("视图模式", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(mode == .terminal ? terminalChromeBG : Palette.settingsBG)
    }

    // MARK: - 后台进程注册表与控制面板

    private var processRegistryPanel: some View {
        List {
            SettingsHeroCard(
                symbol: "cpu",
                tint: Palette.tintSkyInk,
                title: "后台进程注册表",
                subtitle: "监控 Hermes 宿主机活跃进程，支持一键发送 SIGTERM 优雅停止或 SIGKILL 强制终止。",
                statusText: connectionState == .connected ? "\(processes.count) 个活跃进程" : connectionState.label,
                statusTone: connectionState.tone
            )

            if let processNotice {
                Section {
                    Text(processNotice)
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.inkSecondary)
                    TextField("按 PID 或命令筛选进程…", text: $processSearch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                if isRefreshingProcesses && processes.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        ProgressView()
                        Text("正在采样宿主机进程表…")
                            .font(.rowSubtitle)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                } else if filteredProcesses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(connectionState == .connected ? "暂无进程快照" : "终端未连接")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Text("点击右上角刷新按钮，通过宿主机 PTY 实时拉取前 25 个活跃进程。")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, 6)
                } else {
                    ForEach(filteredProcesses) { proc in
                        processRow(proc)
                    }
                }
            } header: {
                SettingsSectionHeader("运行中进程 (CPU 排序)")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Button {
                    mode = .terminal
                    sendRaw("tail -n 40 /tmp/oneday_bg.log\r")
                    Haptics.selection()
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "doc.text.magnifyingglass", color: Palette.tintSkyInk)
                        Text("在终端查看后台任务日志 (/tmp/oneday_bg.log)")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                SettingsSectionHeader("快捷观测")
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
    }

    private func processRow(_ proc: HostProcessEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("PID \(proc.pid)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(Palette.tintSkyInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Palette.tintSky, in: Capsule())

                Text("CPU \(proc.cpu)% · MEM \(proc.mem)% · \(proc.elapsed)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)

                Spacer()
            }

            Text(proc.command)
                .font(.footnote.monospaced())
                .foregroundStyle(Palette.ink)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button("SIGTERM 停止") {
                    sendSignal(pid: proc.pid, signal: "TERM")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("SIGKILL 强杀", role: .destructive) {
                    sendSignal(pid: proc.pid, signal: "KILL")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
    }

    private func refreshProcesses() {
        guard connectionState == .connected else {
            connect()
            return
        }
        isRefreshingProcesses = true
        capturingProcessList = true
        processCaptureBuffer = ""
        let cmd = "echo \(Self.psStartMarker); ps -eo pid=,pcpu=,pmem=,etime=,args= | sort -k2 -nr | head -n 25; echo \(Self.psEndMarker)\r"
        sendRaw(cmd)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if capturingProcessList {
                capturingProcessList = false
                isRefreshingProcesses = false
                parseCapturedProcesses()
            }
        }
    }

    private func sendSignal(pid: Int, signal: String) {
        sendRaw("kill -\(signal) \(pid)\r")
        processNotice = "已向 PID \(pid) 发送 SIG\(signal)。"
        Haptics.selection()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            refreshProcesses()
        }
    }

    private func parseCapturedProcesses() {
        guard let startRange = processCaptureBuffer.range(of: Self.psStartMarker) else { return }
        let afterStart = processCaptureBuffer[startRange.upperBound...]
        let body: Substring
        if let endRange = afterStart.range(of: Self.psEndMarker) {
            body = afterStart[..<endRange.lowerBound]
        } else {
            body = afterStart
        }

        var parsed: [HostProcessEntry] = []
        for rawLine in body.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            guard parts.count >= 5, let pid = Int(parts[0]) else { continue }
            let cmd = String(parts[4])
            if cmd.contains(Self.psStartMarker) || cmd.contains("ps -eo pid=") { continue }
            parsed.append(
                HostProcessEntry(
                    pid: pid,
                    cpu: String(parts[1]),
                    mem: String(parts[2]),
                    elapsed: String(parts[3]),
                    command: cmd
                )
            )
        }
        if !parsed.isEmpty {
            processes = parsed
        }
    }

    // MARK: - 终端深色画布语义色令牌（遵循 OneDayDesign 纪律，消除散落裸色）

    private var terminalCanvasBG: Color { Color(red: 0.08, green: 0.09, blue: 0.11) }
    private var terminalChromeBG: Color { Color(red: 0.05, green: 0.06, blue: 0.08) }
    private var terminalInkPrimary: Color { Color(red: 0.88, green: 0.94, blue: 0.90) }
    private var terminalInkSecondary: Color { Color(red: 0.66, green: 0.70, blue: 0.74) }
    private var terminalKeyFill: Color { Color(red: 0.16, green: 0.18, blue: 0.22) }

    // MARK: - 实时 PTY 终端视图

    private var headerBar: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            SettingsStatusPill(text: connectionState.label, tone: connectionState.tone)
            if let host = appState.config?.host {
                Text(host)
                    .font(.metaMonospaced)
                    .foregroundStyle(terminalInkSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("新会话", isOn: $startFresh)
                .labelsHidden()
                .tint(Palette.primary)
            Text("新会话")
                .font(.caption)
                .foregroundStyle(terminalInkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(terminalChromeBG)
    }

    private var terminalCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let statusBanner {
                        Text(statusBanner)
                            .font(.metaMonospaced)
                            .foregroundStyle(Palette.warning)
                            .padding(.bottom, 4)
                    }
                    if outputBuffer.isEmpty {
                        Text(connectionState == .connecting
                             ? "正在连接 Hermes 宿主机 PTY (WS /api/pty)…"
                             : "终端输出将实时显示在此处。可输入命令或点击下方快捷控制键。")
                            .font(.metaMonospaced)
                            .foregroundStyle(terminalInkSecondary)
                    } else {
                        Text(outputBuffer)
                            .font(.metaMonospaced)
                            .foregroundStyle(terminalInkPrimary)
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
                withAnimation(MotionTokens.resolved(MotionTokens.streamIn, reduceMotion: reduceMotion)) {
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
        .background(terminalChromeBG)
    }

    private func quickKeyButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(terminalInkPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(terminalKeyFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var inputComposer: some View {
        HStack(spacing: 8) {
            TextField("输入命令并发送…", text: $commandInput)
                .font(.callout.monospaced())
                .foregroundStyle(terminalInkPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(terminalKeyFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit {
                    submitCommand()
                }

            Button {
                submitCommand()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(connectionState == .connected ? Palette.primary : Palette.inkMuted)
            }
            .disabled(connectionState != .connected)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(terminalChromeBG)
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
        if raw.hasPrefix("{\"type\":\"resume\"") { return }
        let cleaned = stripANSI(raw)
        if capturingProcessList {
            processCaptureBuffer.append(cleaned)
            if processCaptureBuffer.contains(Self.psEndMarker) {
                capturingProcessList = false
                isRefreshingProcesses = false
                parseCapturedProcesses()
            }
        }
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
