import Foundation
import OneDayCore

/// 盒终端错误：与各桥同分法——「没有钥匙」「钥匙被拒
/// （401）」是桥未连接；端点 404 是「电脑终端尚未开通」
/// （桥还没部署 shell 面）；其余失败给人话、不混报。
enum BoxShellError: Error, Sendable, Equatable {
    case noKey
    case unauthorized
    case notAvailable
    case failed(String)
}

/// 盒终端客户端（P9，契约 box-shell-contract-20261109.md）：
/// POST /api/box-bridge/shell，鉴权与盒桥同一把 Keychain
/// 桥钥匙。桥侧 shell 面尚未部署（归独立服务端小包），
/// 现网请求会 404——客户端据此如实报「尚未开通」，不拿
/// 假回显冒充。命令只由用户逐条手输、本客户端不预置、
/// 不自动重发任何命令。超时 100 秒（唤醒＋执行，与
/// /act 同档，nginx 上限 120 秒之内）。
final class BoxShellClient: @unchecked Sendable {
    /// C-10 收敛：连接/单钥/管线/文案走统一基座（传输
    /// 文案以 endpoint＝「终端」代入，与旧口径逐字同），
    /// 本类只留路径与状态口径
    private let base = BridgeClientBase<BoxShellError>(
        pathPrefix: "/api/box-bridge", timeout: 100,
        noKey: .noKey, failed: BoxShellError.failed
    )

    func run(
        config: ServerConfig, command: String
    ) async throws -> BoxShellResponse {
        _ = try base.requireKey()
        let bodyData: Data
        do {
            bodyData = try base.encoder.encode(
                BoxShellRequest(command: command)
            )
        } catch {
            throw BoxShellError.failed(L10n.string("命令组装失败"))
        }
        let (data, http) = try await base.perform(
            config: config, path: "/shell", method: "POST",
            bodyData: bodyData, endpoint: L10n.string("终端")
        )
        if http.statusCode == 404 {
            throw BoxShellError.notAvailable
        }
        if http.statusCode == 401 {
            throw BoxShellError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw BoxShellError.failed(L10n.format("终端返回 %@", String(http.statusCode)))
        }
        return try base.decode(
            data,
            orThrow: BoxShellError.failed(L10n.string("终端返回格式无法识别"))
        )
    }
}
