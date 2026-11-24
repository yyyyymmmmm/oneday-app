import OneDayCore
import OneDayDesign
import SwiftUI

/// 版本与更新段（DESIGN §360；台账 36，H12 自更新
/// 感知面，用户 2026-11-22 裁定案 A：只读感知）：
/// 当前服务器详情页内一段——当前版本／发布日期／
/// 配置版本对照／托管说明／更新回执，全只读。
///
/// 案 A 红线：服务端明文 can_update_hermes=false
/// （容器部署、升级走运维侧换镜像＋部署包流程），
/// 本段永不出现检查/执行更新的入口——点了没用的
/// 钮即僵尸功能；托管态只如实陈述托管事实（与官方
/// Dashboard 在 can_update=false 时整段不渲染更新
/// UI 的正形一致，感知在内、执行在外）。
///
/// 取数三路逐项隔离（§357 口径）：/api/status（免
/// 登录）与 update/check、update/receipt（Dashboard
/// 会话、走 AppState.performAdmin）互不拖累——一
/// 路失败只落该路的失败形态；字段拉不到显「未记
/// 录」、回执 404 显「暂无更新记录」，不编造。本段
/// 不落盘缓存：每次进页现拉，无旧数据冒充新鲜之面。

// MARK: - 数据

@MainActor
@Observable
final class ServerVersionStore {
    /// 回执形态：404 空态是本部署常态，与失败严格分型
    enum ReceiptState: Equatable {
        case pending
        /// 404：暂无更新记录（常态，不是失败）
        case absent
        /// 有回执：值为服务端摘要原话（回落链见
        /// UpdateReceiptResponse.displayText）
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
    /// check 路失败（非过期）：只影响版本回落与托管
    /// 旁证，状态面在位时段主体不受影响，不单独成行
    private(set) var checkFailed = false
    private(set) var sessionExpired = false
    private(set) var receiptState: ReceiptState = .pending

    var facts: ServerVersionFacts {
        ServerVersionBuilder.facts(status: status, check: check)
    }

    /// 取数三路（测试缝）：status 直读；check/receipt
    /// 由 load(appState:) 侧包 performAdmin 注入
    /// （401 静默重登一次、再 401 落 sessionExpired）
    struct Fetchers {
        var status: (ServerConfig) async throws -> ServerStatus
        var updateCheck: () async throws -> UpdateCheckResponse
        var updateReceipt: () async throws -> UpdateReceiptResponse
    }

/// §416 新鲜度普查豁免：版本状态面，进面读现值（判定表见 DESIGN §416）
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
        // 三路顺序取数、逐项隔离：一路失败只落该路
        // 形态，不拖其余两路（同 §357 的失败隔离口
        // 径；并发与否是实现细节——取数闭包为非
        // Sendable 的测试缝形态，Swift 6 隔离域下不
        // 许送进子任务，故顺序执行，Grants/Health-
        // Check 两 Store 同此式）
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

// MARK: - 段本体

struct ServerVersionSection: View {
    @Environment(AppState.self) private var appState
    @State private var store = ServerVersionStore()

    var body: some View {
        SectionLabel("版本与更新")
            .padding(.top, OneDayMetrics.sectionOuterSpacing)
            .padding(.bottom, OneDayMetrics.spacingS)
        VStack(spacing: 0) {
            content
        }
        .odGroup()
        .task(id: appState.config?.baseString ?? "") {
            await store.load(appState: appState)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = store.unavailableMessage {
            plainRow(message)
        } else if !store.hasLoaded {
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在读取…")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                Spacer()
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
        } else {
            factRow("当前版本", value: versionText)
            GroupDivider()
            factRow(
                "发布日期",
                value: store.statusFailed
                    ? "拉取失败" : store.facts.releaseDateText
            )
            GroupDivider()
            factRow(
                "配置版本",
                value: store.statusFailed
                    ? "拉取失败" : store.facts.configVersionText
            )
            if let note = store.facts.managedNote {
                GroupDivider()
                footnoteRow(note)
            }
            GroupDivider()
            factRow("更新回执", value: receiptText)
            if store.sessionExpired {
                GroupDivider()
                footnoteRow("面板会话已过期，重新登录后可读更新检查与回执。")
            }
        }
    }

    /// 版本行：状态面失败时以检查面的 current_version
    /// 回落（同为服务端原话）；两路皆无才报拉取失败
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

    /// 键值行：与服务器详情既有行件同几何（横向
    /// spacingM、minHeight rowHeight），值右对齐次级色
    private func factRow(_ label: String, value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.body)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    /// 说明行：脚注样式（部署形态不是异常，不做警告卡）
    private func footnoteRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
    }

    private func plainRow(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.vertical, OneDayMetrics.spacingSM)
    }
}
