import Foundation
import OneDayCore

/// 云电脑连接中枢（0.37.0 模型包·接入层同面）：数据
/// 走伴生 connections 契约（CompanionFrontClient），
/// 状态词表与面板同源（Core ConnectionStatusWording）。
/// 凭据提交的成败与回滚都在服务端：front 验活不过会
/// 自己撤回改动并在 detail 里说明，App 回显前先过
/// §233 安全门（ServerErrorText）——过门原样、不过
/// 门落通用人话、原文只进诊断留痕，不许给什么显什
/// 么；验活状态转移走 Core CredentialFlowPhase 状态机。
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

    /// 云电脑凭据镜像（从 Hermes 拉取的明文，供界面显示与编辑）
    private(set) var boxCredentialMirror: BoxCredentialPayload?
    private(set) var loadingCredential = false
    private(set) var credentialError: String?

    var cloudComputers: [CompanionConnection] {
        connections.filter(\.isCloudComputer)
    }

    /// 拉取云电脑凭据镜像（Hermes 单一真源）
    func fetchBoxCredential(id: String, appState: AppState) async {
        guard !loadingCredential, let config = appState.config else { return }
        loadingCredential = true
        defer { loadingCredential = false }
        do {
            boxCredentialMirror = try await client.fetchCredential(config: config, id: id)
            credentialError = nil
        } catch let error as OneDayBridgeError {
            credentialError = error.userFacingText
            boxCredentialMirror = nil
        } catch {
            credentialError = L10n.string("凭据没读出来，请稍后再试。")
            boxCredentialMirror = nil
        }
    }

/// §416 新鲜度普查豁免：探测复合面一环（进页/下拉同序，含本地/设备探测），门不介入（判定表见 DESIGN §416）
    func load(appState: AppState) async {
        guard !isLoading, let config = appState.config else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            connections = try await client.connections(
                config: config
            ).map { sanitized($0) }
            loadError = nil
        } catch let error as OneDayBridgeError {
            loadError = error == .noKey
                ? L10n.string("还没有登录凭据，读不到电脑列表。")
                : L10n.string("电脑列表没读出来，可能是网络或服务暂时没响应")
        } catch {
            loadError = L10n.string("电脑列表没读出来，可能是网络或服务暂时没响应")
        }
    }

    /// 最近一次生成的内网穿透配对命令（按连接 ID 暂存内存，方便复制）
    private(set) var latestPairings: [String: ReverseNodePairing] = [:]

    /// 添加电脑/远程主机两步：先建记录，再填凭据或复制配对命令
    func createComputer(
        provider: String, name: String, osType: String? = nil, appState: AppState
    ) async -> CompanionConnection? {
        guard let config = appState.config else { return nil }
        do {
            let result = try await client.createConnection(
                config: config, provider: provider, name: name, osType: osType
            )
            if let pairing = result.pairing {
                latestPairings[result.connection.id] = pairing
            }
            await load(appState: appState)
            return connections.first { $0.id == result.connection.id }
                ?? sanitized(result.connection)
        } catch {
            notice = L10n.string("这台电脑没能加上，请稍后再试。")
            return nil
        }
    }

    func resetCredentialPhase() {
        credentialPhase = .idle
    }

    /// 提交凭据（状态机驱动）
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
            if let pairing = result.pairing {
                latestPairings[id] = pairing
            }
            credentialPhase = CredentialFlowPhase.next(
                from: credentialPhase,
                receipt: (
                    ok: result.ok,
                    detail: safeDetail(
                        result.detail,
                        fallback: result.ok
                            ? L10n.string("凭据已提交。")
                            : L10n.string("提交没能完成，请稍后再试。")
                    )
                )
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

    /// 生成服务端托管 Ed25519 SSH 密钥对
    func generateSSHKeypair(
        id: String, appState: AppState
    ) async -> SSHKeygenReceipt? {
        guard let config = appState.config else { return nil }
        do {
            let receipt = try await client.generateSSHKeypair(config: config, id: id)
            if let updated = receipt.connection {
                replace(updated)
            }
            return receipt
        } catch let error as OneDayBridgeError {
            notice = error.userFacingText
            return nil
        } catch {
            notice = L10n.string("生成 SSH 密钥失败，请稍后再试。")
            return nil
        }
    }

    /// 重新验活（详情页按钮）
    func verify(id: String, appState: AppState) async {
        guard let config = appState.config else { return }
        do {
            let result = try await client.verify(config: config, id: id)
            if let updated = result.connection { replace(updated) }
            if let detail = ServerErrorText.userSafe(result.detail) {
                notice = result.ok
                    ? L10n.format("连接正常：%@", detail)
                    : L10n.format("没连上：%@", detail)
            } else {
                ChatDiagTrace.record(
                    "连接验活 detail 未过安全门：\(result.detail)"
                )
                notice = result.ok
                    ? L10n.string("连接正常。")
                    : L10n.string("没连上，请稍后再试。")
            }
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

    func deleteComputer(id: String, appState: AppState) async -> Bool {
        guard let config = appState.config else { return false }
        do {
            try await client.deleteConnection(config: config, id: id)
            connections.removeAll { $0.id == id }
            latestPairings.removeValue(forKey: id)
            notice = L10n.string("已删除。")
            return true
        } catch let error as OneDayBridgeError {
            notice = error.userFacingText
            return false
        } catch {
            notice = L10n.string("删除没能完成，请稍后再试。")
            return false
        }
    }

    private func replace(_ connection: CompanionConnection) {
        let connection = sanitized(connection)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
    }

    /// 服务端 detail 安全出口（§233 件八）：过
    /// ServerErrorText 门返回修剪后的原文；不过门原
    /// 文只进诊断留痕、呈现落 fallback 通用人话
    private func safeDetail(
        _ raw: String, fallback: String
    ) -> String {
        if let safe = ServerErrorText.userSafe(raw) {
            return safe
        }
        ChatDiagTrace.record("连接回执 detail 未过安全门：\(raw)")
        return fallback
    }

    /// 连接记录入店收口：lastVerify.detail 是服务端
    /// 落字、详情页原文呈现——入店前过安全门，过门
    /// 用修剪值，不过门以通用句替换（原文进诊断留痕）
    private func sanitized(
        _ connection: CompanionConnection
    ) -> CompanionConnection {
        var connection = connection
        guard var verify = connection.lastVerify else {
            return connection
        }
        if let safe = ServerErrorText.userSafe(verify.detail) {
            verify.detail = safe
        } else {
            ChatDiagTrace.record(
                "连接验活记录 detail 未过安全门：\(verify.detail)"
            )
            verify.detail = verify.ok
                ? L10n.string("连接正常。")
                : L10n.string("没连上，请稍后再试。")
        }
        connection.lastVerify = verify
        return connection
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
