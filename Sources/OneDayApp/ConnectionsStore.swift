import Foundation
import OneDayCore

/// 云电脑连接中枢（0.37.0 模型包·接入层同面）：数据
/// 走伴生 connections 契约（CompanionFrontClient），
/// 状态词表与面板同源（Core ConnectionStatusWording）。
/// 凭据提交的成败与回滚都在服务端：front 验活不过会
/// 自己撤回改动并在 detail 里说明，App 只如实回显，
/// 验活状态转移走 Core CredentialFlowPhase 状态机。
@MainActor
@Observable
final class ConnectionsStore {
    private(set) var connections: [CompanionConnection] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    /// 凭据流（添加/更换共用一个在飞状态）
    private(set) var credentialPhase: CredentialFlowPhase = .idle
    var notice: String?

    private let client = CompanionFrontClient()

    var cloudComputers: [CompanionConnection] {
        connections.filter(\.isCloudComputer)
    }

    func load(appState: AppState) async {
        guard !isLoading, let config = appState.config else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            connections = try await client.connections(config: config)
            loadError = nil
        } catch let error as OneDayBridgeError {
            loadError = error == .noKey
                ? L10n.string("还没有登录凭据，读不到电脑列表。")
                : L10n.string("电脑列表读取失败，请稍后再试。")
        } catch {
            loadError = L10n.string("电脑列表读取失败，请稍后再试。")
        }
    }

    /// 添加电脑两步：先建记录（只有名字与类型），再由
    /// 详情/表单提交凭据验活。建记录失败返回 nil。
    func createComputer(
        provider: String, name: String, appState: AppState
    ) async -> CompanionConnection? {
        guard let config = appState.config else { return nil }
        do {
            let created = try await client.createConnection(
                config: config, provider: provider, name: name
            )
            await load(appState: appState)
            return connections.first { $0.id == created.id } ?? created
        } catch {
            notice = L10n.string("这台电脑没能加上，请稍后再试。")
            return nil
        }
    }

    /// 提交凭据（状态机驱动）：回执 ok/detail 原样进
    /// 状态——detail 是服务端人话（含回滚说明），不加工。
    func submitCredential(
        id: String, body: [String: JSONValue], appState: AppState
    ) async {
        guard let config = appState.config else { return }
        credentialPhase = CredentialFlowPhase.next(
            from: credentialPhase, submitted: true
        )
        do {
            let result = try await client.submitCredential(
                config: config, id: id, body: body
            )
            credentialPhase = CredentialFlowPhase.next(
                from: credentialPhase,
                receipt: (ok: result.ok, detail: result.detail)
            )
            if let updated = result.connection {
                replace(updated)
            } else {
                await load(appState: appState)
            }
        } catch let error as OneDayBridgeError {
            credentialPhase = CredentialFlowPhase.next(
                from: credentialPhase,
                receipt: (ok: false, detail: error.userFacingText)
            )
        } catch {
            credentialPhase = CredentialFlowPhase.next(
                from: credentialPhase,
                receipt: (ok: false, detail: L10n.string("提交没能完成，请稍后再试。"))
            )
        }
    }

    /// 重新验活（详情页按钮）：结果直接刷新该行记录，
    /// 成败一句回显
    func verify(id: String, appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            let result = try await client.verify(config: config, id: id)
            if let updated = result.connection { replace(updated) }
            notice = result.ok
                ? L10n.format("连接正常：%@", result.detail)
                : L10n.format("没连上：%@", result.detail)
        } catch {
            notice = L10n.string("测试连接没能完成，请稍后再试。")
        }
    }

    func disconnect(id: String, appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            let updated = try await client.disconnect(config: config, id: id)
            if let updated { replace(updated) }
            notice = L10n.string("已断开。")
        } catch {
            notice = L10n.string("断开没能完成，请稍后再试。")
        }
    }

    private func replace(_ connection: CompanionConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
    }
}

/// OneDayBridgeError 的人话出口（连接面自用；其余桥面
/// 各有既有口径，不在此扩散）
extension OneDayBridgeError {
    var userFacingText: String {
        switch self {
        case .noKey: return L10n.string("还没有登录凭据。")
        case .unauthorized: return L10n.string("登录凭据被拒绝，请重新登录后再试。")
        case .bridgeMissing: return L10n.string("这个功能面还没开通。")
        case .recordGone: return L10n.string("这条记录已经不在了。")
        case .failed(let message): return message
        }
    }
}
