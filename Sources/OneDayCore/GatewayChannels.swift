import Foundation

/// 网关渠道（0.37.0 模型包·接入层只读）：自建网关里
/// 的渠道＝一家上游接入点（地址＋密钥＋可用模型）。
/// 用户 2026-11-10 19:07 定调：渠道在用户任务里就是
/// 模型配置，须在 App 里看得见；管理凭据只在服务端
/// 管理面手里，App 永不持有。本包只读展示先行：数据
/// 经伴生管理面读端点（GET /api/companion/gateway-
/// channels）——该面 2026-11-11 实测未开通（404），
/// 客户端把「面不存在」与「读失败」分开，UI 如实
/// 露面，不放假数据、假按钮。
public struct GatewayChannel: Codable, Equatable, Identifiable, Sendable {
    /// 网关侧渠道编号（字符串化，展示为「渠道 N」）
    public var id: String
    public var name: String
    /// 服务端状态原值（enabled/disabled/…），呈现经 wording
    public var status: String
    /// 该渠道声明可用的模型
    public var models: [String]
    /// 优先级（数值越高越优先）；读面没给时为 nil
    public var priority: Int?
    /// 同优先级内的分流权重；没给时为 nil
    public var weight: Int?
    /// 分组；没给时为 nil
    public var group: String?

    public init(
        id: String, name: String, status: String, models: [String],
        priority: Int?, weight: Int?, group: String?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.models = models
        self.priority = priority
        self.weight = weight
        self.group = group
    }

    /// 状态人话（宪法 §8）：已知值给准话，未知值如实
    /// 显示「状态未知」，不猜
    public var statusWording: String {
        switch status.lowercased() {
        case "enabled", "enable", "1", "active", "on":
            return "使用中"
        case "disabled", "disable", "0", "off", "manually_disabled":
            return "已停用"
        case "auto_disabled":
            return "出错后自动停用"
        default:
            return "状态未知"
        }
    }

    /// 副行摘要：模型数＋（有才写的）优先级/分组
    public var detailLine: String {
        var parts: [String] = ["可用模型 \(models.count) 个"]
        if let priority { parts.append("优先级 \(priority)") }
        if let group, !group.isEmpty { parts.append("分组 \(group)") }
        return parts.joined(separator: " · ")
    }
}

/// 渠道读面回执 {channels: […]}
public struct GatewayChannelsResponse: Codable, Equatable, Sendable {
    public var channels: [GatewayChannel]

    public init(channels: [GatewayChannel]) {
        self.channels = channels
    }
}

/// 渠道区呈现状态（四态如实）：面未开通与读失败是
/// 两回事，文案分开，不许用空列表冒充任何一种。
public enum GatewayChannelsFace: Equatable, Sendable {
    case loading
    /// 管理面读端点不存在（404）：本包留位、待伴生开通
    case faceMissing
    case failed(String)
    case ready([GatewayChannel])

    /// 区内说明文案（ready 态 nil＝不占行）
    public var placeholderText: String? {
        switch self {
        case .loading:
            return "正在读取网关渠道…"
        case .faceMissing:
            return "网关渠道的管理面还没开通，这里先留位。渠道的启停与顺序暂时只能在网关那边改，这里的清单开通后会直接显示。"
        case .failed(let message):
            return message
        case .ready(let channels):
            return channels.isEmpty
                ? "网关里还没有渠道记录。" : nil
        }
    }
}
