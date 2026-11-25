import OneDayCore
import OneDayDesign
import SwiftUI

/// 版本与更新段（DESIGN §360；台账 36，H12 自更新感知面，案 A：只读感知）：
/// 统一为原生 List Section，直接嵌入 ServerDetailView，不再套用外层透明 Section 与 .odGroup()。

// MARK: - 数据

@MainActor
@Observable
final class ServerVersionStore {
    /// 回执形态：404 空态是本部署常态，与失败严格分型
    enum ReceiptState: Equatable {
        case pending
        /// 404：暂无更新记录（常态，不是失败）
        case absent
        /// 有回执：值为服务端摘要原话
        case present(String)
        case failed
        case sessionExpired
    }

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 未连接（无配置）：整段如实不可用，不冒充空数据
    private(set) var unavailableMessage: String?
    private(set) var status: ServerStatus?
    private(set) var statusFailed = false
    private(set) var check: UpdateCheckResponse?
    private(set) var checkFailed = false
    private(set) var sessionExpired = false
    private(set) var receiptState: ReceiptState = .pending

    var facts: ServerVersionFacts {
        ServerVersionBuilder.facts(status: status, check: check)
    }

    struct Fetchers {
        var status: (ServerConfig) async throws -> ServerStatus
        var updateCheck: () async throws -> UpdateCheckResponse
        var updateReceipt: () async throws -> UpdateReceiptResponse
    }

    func load(appState: AppState) async {
        guard let config = appState.config else {
            unavailableMessage =
                "还没连上服务器，连上后这里会显示这台服务器的版本信息。"
            hasLoaded = true
            return
        }
        await load(
            config: config,
            fetchers: Fetchers(
                status: { try await appState.client.status(config: $0) },
                updateCheck: {
                    try await appState.performAdmin { client, cfg in
                        try await client.updateCheck(config: cfg)
                    }
                },
                updateReceipt: {
                    try await appState.performAdmin { client, cfg in
                        try await client.updateReceipt(config: cfg)
                    }
                }
            )
        )
    }

    func load(config: ServerConfig, fetchers: Fetchers) async {
        guard !isLoading else { return }
        unavailableMessage = nil
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            status = try await fetchers.status(config)
            statusFailed = false
        } catch {
            statusFailed = true
        }
        do {
            check = try await fetchers.updateCheck()
            checkFailed = false
        } catch {
            if Self.isSessionExpired(error) {
                sessionExpired = true
            } else {
                checkFailed = true
            }
        }
        do {
            let value = try await fetchers.updateReceipt()
            receiptState = .present(value.displayText)
        } catch {
            if (error as? UpdateReceiptError) == .absent {
                receiptState = .absent
            } else if Self.isSessionExpired(error) {
                receiptState = .sessionExpired
                sessionExpired = true
            } else {
                receiptState = .failed
            }
        }
    }

    private nonisolated static func isSessionExpired(_ error: Error) -> Bool {
        guard let hermes = error as? HermesError else { return false }
        if case .sessionExpired = hermes { return true }
        return false
    }
}

// MARK: - 原生 Section 本体

struct ServerVersionSection: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServerVersionStore()

    var body: some View {
        Section {
            content
        } header: {
            SettingsSectionHeader("版本与更新")
        } footer: {
            footerContent
        }
        .listRowBackground(Palette.surface)
        .task(id: appState.config?.baseString ?? "") {
            await store.load(appState: appState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.unavailableMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        } else if !store.hasLoaded {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在读取…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .frame(minHeight: OneDayMetrics.settingsRowHeight)
        } else {
            SettingsValueRow(title: "当前版本", value: versionText)
            SettingsValueRow(
                title: "发布日期",
                value: store.statusFailed
                    ? "拉取失败" : store.facts.releaseDateText
            )
            SettingsValueRow(
                title: "配置版本",
                value: store.statusFailed
                    ? "拉取失败" : store.facts.configVersionText
            )
            SettingsValueRow(title: "更新回执", value: receiptText)
        }
    }

    @ViewBuilder
    private var footerContent: some View {
        let notes: [String] = [
            store.hasLoaded ? store.facts.managedNote : nil,
            store.sessionExpired
                ? "面板会话已过期，重新登录后可读更新检查与回执。" : nil,
        ].compactMap { $0 }

        if !notes.isEmpty {
            Text(notes.joined(separator: "\n"))
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var versionText: String {
        if store.statusFailed, store.check == nil {
            return "拉取失败"
        }
        return store.facts.versionText
    }

    private var receiptText: String {
        switch store.receiptState {
        case .pending:
            return "正在读取…"
        case .absent:
            return "暂无更新记录"
        case .present(let text):
            return text
        case .failed:
            return "拉取失败"
        case .sessionExpired:
            return "未读取"
        }
    }
}
