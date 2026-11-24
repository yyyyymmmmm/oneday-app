import OneDayCore
import OneDayDesign
import SwiftUI

/// 电脑面「终端」段（P9，契约 box-shell-contract-
/// 20261109.md）：在智能体的云电脑里逐条手输命令、
/// 看真实回显。命令历史只存当次会话内存（不落盘、
/// 离面即弃），输出走 codeFill 等宽面（设计标准
/// §7 P9 锚）。桥 shell 面未部署时整段如实露「尚未
/// 开通」，不拿假回显冒充；桥未连接与开通是两态分开。
struct BoxTerminalView: View {
    @Environment(AppState.self) private var appState
    private let client = BoxShellClient()

    private struct Exchange: Identifiable {
        let id = UUID()
        let command: String
        var response: BoxShellResponse?
        var failureNote: String?
    }

    private enum Phase {
        case ready
        case notConnected
        case notAvailable
    }

    @State private var phase: Phase = .ready
    @State private var commandText = ""
    @State private var running = false
    @State private var exchanges: [Exchange] = []

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            switch phase {
            case .notConnected:
                EmptyState(
                    icon: "key.slash",
                    title: "还没连上你的服务",
                    message: "还没有可用的登录信息：在电脑里执行命令用的是你的 Hermes 登录。先到「设置」里确认已经连接并登录，就能用了。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
                Spacer()
            case .notAvailable:
                EmptyState(
                    icon: "terminal",
                    title: "电脑终端尚未开通",
                    message: "智能体电脑的终端面还在路上；开通后这里能直接在它电脑里逐条执行命令。"
                )
                .padding(.top, OneDayMetrics.spacingXXL)
                Spacer()
            case .ready:
                readyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.pageBG)
    }

    private var readyContent: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            Text("命令在智能体的云电脑里执行（工作目录 /workspace），逐条手输、点执行才发出；离开本页后记录不保留。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
            HStack(spacing: OneDayMetrics.spacingS) {
                TextField("输入命令，如 uname -a", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { submit() }
                Button("执行") { submit() }
                    .buttonStyle(.bordered)
                    .disabled(
                        running
                            || BoxShellCommandText.normalize(commandText) == nil
                    )
            }
            if running {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView().controlSize(.small)
                    Text("执行中…电脑休眠时要先唤醒，会慢一些。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                    ForEach(exchanges.reversed()) { exchange in
                        exchangeBlock(exchange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, OneDayMetrics.pageGutter)
        .padding(.vertical, OneDayMetrics.spacingM)
    }

    private func exchangeBlock(_ exchange: Exchange) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            Text("$ \(exchange.command)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
            if let response = exchange.response {
                Text(response.outputText)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(
                        response.succeeded
                            ? Palette.ink : Palette.danger
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let exitCode = response.exitCode, exitCode != 0 {
                    Text("退出码 \(exitCode)")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                if response.wasTruncated {
                    Text("输出较长，已被截断。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if let note = exchange.failureNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
        .padding(OneDayMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.codeFill,
            in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview, style: .continuous)
        )
    }

    private func submit() {
        guard let command = BoxShellCommandText.normalize(commandText),
              !running else { return }
        guard let config = appState.config else {
            phase = .notConnected
            return
        }
        if appState.isDemo {
            exchanges.append(Exchange(
                command: command,
                failureNote: "演示态不执行命令。"
            ))
            commandText = ""
            return
        }
        commandText = ""
        running = true
        let exchange = Exchange(command: command)
        exchanges.append(exchange)
        let exchangeID = exchange.id
        Task {
            defer { running = false }
            do {
                let response = try await client.run(
                    config: config, command: command
                )
                updateExchange(id: exchangeID) { $0.response = response }
            } catch let error as BoxShellError {
                switch error {
                case .noKey, .unauthorized:
                    phase = .notConnected
                case .notAvailable:
                    phase = .notAvailable
                case .failed(let message):
                    updateExchange(id: exchangeID) {
                        $0.failureNote = message
                    }
                }
            } catch {
                updateExchange(id: exchangeID) {
                    $0.failureNote = "命令发送失败。"
                }
            }
        }
    }

    private func updateExchange(
        id: UUID, _ mutate: (inout Exchange) -> Void
    ) {
        guard let index = exchanges.firstIndex(where: { $0.id == id })
        else { return }
        mutate(&exchanges[index])
    }
}
