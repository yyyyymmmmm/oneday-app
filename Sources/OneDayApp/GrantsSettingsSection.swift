import OneDayCore
import OneDayDesign
import SwiftUI

/// 命令授权区（DESIGN §355；Hermes 批 5 客户端面，部署
/// 包 1.3.0）：审批规则页内的第二个区——网关统一授权
/// 清单（GET /v1/grants）的只读镜像＋exec 撤销入口。
/// 与上方「审批规则」区分工（一个功能一个家）：
/// - 本区真源在网关：exec 命令授权（审批卡「总是允许」
///   落的 command_allowlist）＋写闸规则的只读投影；
/// - exec 条目在本区撤销（POST /v1/grants/revoke，连
///   别名一并删）；写闸条目只读呈现——撤销归上方「审
///   批规则」（桥是单一写者），本区不发写闸撤销；
/// - 撤销成败不认回执自报：成功后必重拉清单、以回读
///   不在列为确认（GrantReadback）；失败留人话在区首、
///   清单不假变。

// MARK: - 数据

@MainActor
@Observable
final class GrantsLedgerStore {
    enum State {
        case idle
        case loading
        /// 已连上但清单还没拉到（未连接/无凭据不是失败，
        /// 如实说未就绪）
        case unavailable(String)
        case failed(String)
        case ready(GrantsListResponse)
    }

    private(set) var state: State = .idle
    private(set) var revokingKeys: Set<String> = []
    /// 撤销结果的人话提示（区首呈现）：失败与未确认用
    /// problem 语气、良性结果（已不在）用普通语气
    private(set) var note: String?
    private(set) var noteIsProblem = false

/// §416 新鲜度普查豁免：设置子页清单，写动作回读对账、进面现读（判定表见 DESIGN §416）
    /// 拉统一清单。未连接/无凭据 → .unavailable（不冒充
    /// 空清单）；503 投影不可用给专属人话；其余失败走
    /// HermesError 人话。已有清单时刷新不闪空（保留旧
    /// 清单直到新回包落地）
    func load(appState: AppState) async {
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            state = .unavailable(
                "还没连上服务器，连上后这里会显示已留下的命令授权。"
            )
            return
        }
        if case .ready = state {
            // 刷新中保留现清单
        } else {
            state = .loading
        }
        do {
            let response = try await appState.client.listGrants(
                config: config, apiKey: apiKey
            )
            state = .ready(response)
        } catch let error as HermesError {
            if case .serverError(_, _, let code) = error,
               code == "grant_projection_unavailable" {
                state = .failed(
                    "授权清单暂时读不到（服务端投影不可用），下拉刷新再试。"
                )
            } else {
                state = .failed(error.userMessage)
            }
        } catch {
            state = .failed("授权清单没读出来，请稍后再试。")
        }
    }

    /// 撤销一条 exec 命令授权：POST 成功只是受理——随
    /// 即重拉清单回读确认（不在列才算撤掉）；端点错误
    /// 按 GrantRevokeDirective 分型给人话，清单保持服
    /// 务端原样、不本地假删行
    func revoke(_ entry: GrantEntry, appState: AppState) async {
        guard entry.canRevokeHere,
              let patternKey = entry.patternKey else { return }
        guard !revokingKeys.contains(entry.grantKey) else { return }
        guard let config = appState.config,
              let apiKey = appState.apiKey else {
            note = "还没连上服务器，暂时撤不了。"
            noteIsProblem = true
            return
        }
        revokingKeys.insert(entry.grantKey)
        defer { revokingKeys.remove(entry.grantKey) }
        note = nil
        do {
            _ = try await appState.client.revokeGrant(
                config: config, apiKey: apiKey, patternKey: patternKey
            )
        } catch let error as HermesError {
            await handleRevokeError(error, appState: appState)
            return
        } catch {
            note = "撤销没成功，请稍后再试。"
            noteIsProblem = true
            return
        }
        // 回读确认：重拉清单，被撤键不在列才算数
        await load(appState: appState)
        if case .ready(let refreshed) = state {
            if GrantReadback.isConfirmedAbsent(
                grantKey: entry.grantKey, in: refreshed
            ) {
                note = nil
            } else {
                note = "撤销请求已受理，但最新清单里这条还在，可能还没生效——下拉刷新再确认。"
                noteIsProblem = true
            }
        }
        // 回读本身失败时 state 已是 .failed（load 内如实
        // 呈现），不叠加假结论
    }

    private func handleRevokeError(
        _ error: HermesError, appState: AppState
    ) async {
        let directive: GrantRevokeDirective
        switch error {
        case .serverError(_, let status, let code):
            directive = GrantRevokeDirective.directive(
                status: status, serverCode: code
            )
        case .unexpectedStatus(_, let status):
            directive = GrantRevokeDirective.directive(
                status: status, serverCode: nil
            )
        default:
            directive = .failed
        }
        switch directive {
        case .notFound:
            // 已不在（多为别处刚撤过）：良性，刷新清单对齐
            note = "这条授权已经不在了，清单已刷新。"
            noteIsProblem = false
            await load(appState: appState)
        case .unverified:
            note = "服务端没能确认撤销干净，这条可能还在——下面已是最新清单。"
            noteIsProblem = true
            await load(appState: appState)
        case .wrongChannel:
            note = "这条授权不归这里撤销。"
            noteIsProblem = true
        case .done, .failed:
            note = "撤销没成功：\(error.userMessage)"
            noteIsProblem = true
        }
    }
}

// MARK: - 区视图

/// 「命令授权」区本体：自带加载/未就绪/失败/部分读到
/// 的诚实呈现（与页面其余区互不冒充）；撤销确认框自
/// 挂本区（与审批规则区同一确认文案口径）
struct CommandGrantsSection: View {
    let store: GrantsLedgerStore
    let appState: AppState
    @State private var revokeTarget: GrantEntry?

    var body: some View {
        Section {
            content
        } header: {
            Text("命令授权")
        } footer: {
            Text("在聊天里批准命令时点「总是允许」，同类命令以后直接执行、不再逐条问，并在这里留下一条；撤销后恢复逐条审批。写入规则不在这里撤销——归上方「审批规则」管。")
        }
        .confirmationDialog(
            "撤销这条命令授权？",
            isPresented: Binding(
                get: { revokeTarget != nil },
                set: { if !$0 { revokeTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: revokeTarget
        ) { entry in
            Button("撤销授权", role: .destructive) {
                Task { await store.revoke(entry, appState: appState) }
                revokeTarget = nil
            }
            Button("取消", role: .cancel) {
                revokeTarget = nil
            }
        } message: { entry in
            Text("撤销后，「\(entry.scopeLabel)」这类命令会重新逐条等你审批。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let note = store.note {
            Text(note)
                .font(.caption)
                .foregroundStyle(
                    store.noteIsProblem
                        ? Palette.danger : Palette.inkSecondary
                )
        }
        switch store.state {
        case .idle, .loading:
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在读取授权清单…")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .unavailable(let message), .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Button("重试") {
                Task { await store.load(appState: appState) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .ready(let response):
            readyContent(response)
        }
    }

    @ViewBuilder
    private func readyContent(_ response: GrantsListResponse) -> some View {
        if response.partial {
            Text("有一类授权暂时没读全，下面是读到的部分；下拉刷新可再试。")
                .font(.caption)
                .foregroundStyle(Palette.warningText)
        }
        if response.grants.isEmpty {
            Text(response.partial
                ? "读到的这一类里暂时没有授权，另一类没读到，下拉刷新再看。"
                : "暂无命令授权。在聊天里批准命令时点「总是允许」后，会在这里留下一条，可随时撤销。")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        if !response.execEntries.isEmpty {
            groupHeader("命令")
            ForEach(response.execEntries) { entry in
                execRow(entry)
            }
        }
        if !response.writegateEntries.isEmpty {
            groupHeader("写入规则（只读）")
            ForEach(response.writegateEntries) { entry in
                writegateRow(entry)
            }
        }
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(Palette.inkSecondary)
    }

    private func execRow(_ entry: GrantEntry) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(entry.scopeLabel)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Text(execMeta(entry))
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            if store.revokingKeys.contains(entry.grantKey) {
                ProgressView()
            } else {
                Button("撤销", role: .destructive) {
                    revokeTarget = entry
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }

    private func writegateRow(_ entry: GrantEntry) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(entry.scopeLabel)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            Text(writegateMeta(entry))
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingMicro)
    }

    /// exec 行副行：来源与建立时间都只报契约里有的——
    /// 来源决定查不到说「来源未记录」、时间查不到说
    /// 「建立时间未记录」，不编
    private func execMeta(_ entry: GrantEntry) -> String {
        var parts: [String] = []
        parts.append(
            entry.sourceDecision != nil
                ? "经审批时「总是允许」" : "来源未记录"
        )
        if let grantedAt = entry.grantedAt {
            parts.append("建立于 \(ApprovalTimeText.relative(grantedAt))")
        } else {
            parts.append("建立时间未记录")
        }
        return parts.joined(separator: " · ")
    }

    private func writegateMeta(_ entry: GrantEntry) -> String {
        var parts: [String] = []
        if let grantedAt = entry.grantedAt {
            parts.append("建立于 \(ApprovalTimeText.relative(grantedAt))")
        } else {
            parts.append("建立时间未记录")
        }
        parts.append("在上方「审批规则」里管理")
        return parts.joined(separator: " · ")
    }
}
