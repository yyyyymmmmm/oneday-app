import Foundation

/// 三步探活与各接口的失败口径：每个 case 自带「人话」文案，
/// 连接页与各功能页直接显示 userMessage，不许把状态码甩给用户。
public enum HermesError: Error, Sendable {
    /// 地址归一化失败（连接页表单层）
    case invalidServerAddress
    /// 网络层失败：连不上、超时、DNS 等（附系统错误简述）
    case unreachable(String)
    /// 第一步 /health 非 200
    case healthCheckFailed(status: Int)
    /// 第二步登录被拒：账号或密码不对（401/403/422）
    case loginRejected
    /// 第二步登录返回了非预期状态
    case loginFailed(status: Int)
    /// 第三步 API 密钥被拒（401/403）
    case apiKeyRejected
    /// 接口返回非预期状态（附接口名与状态码）
    case unexpectedStatus(endpoint: String, status: Int)
    /// 响应解码失败（版本不匹配的典型信号）
    case decodingFailed(endpoint: String)
    /// 会话过期且自动重登失败
    case sessionExpired
    /// 用户主动停止生成 / 取消任务
    case cancelled

    public var userMessage: String {
        switch self {
        case .invalidServerAddress:
            return "服务器地址看起来不对，检查一下再试。"
        case .unreachable(let detail):
            return "连不上服务器（\(detail)）。检查地址是否正确、服务器是否在线。"
        case .healthCheckFailed(let status):
            return "服务器健康检查没通过（状态 \(status)），可能不是 Hermes 服务，或版本太旧。"
        case .loginRejected:
            return "登录被拒：面板账号或密码不对。"
        case .loginFailed(let status):
            return "登录失败（状态 \(status)），请稍后再试。"
        case .apiKeyRejected:
            return "API 密钥被拒：检查密钥是否填对、是否已被撤销。"
        case .unexpectedStatus(let endpoint, let status):
            return "\(endpoint) 返回了状态 \(status)，请稍后再试。"
        case .decodingFailed(let endpoint):
            return "\(endpoint) 的返回看不懂，可能是服务端版本与 App 不匹配。"
        case .sessionExpired:
            return "登录已过期，重新登录后再试。"
        case .cancelled:
            return "已取消。"
        }
    }
}
