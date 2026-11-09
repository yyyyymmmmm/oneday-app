import Foundation

// MARK: - GET /api/tools/computer-use/status（留口就绪态）

public enum ComputerUseReadiness: String, Equatable, Sendable {
    case ready
    case notReady
    case unknown
}

/// computer-use 就绪态宽容模型（phase3-data-design §6.2）：
/// OpenAPI 对该端点 200 响应只给了空 schema——先用
/// JSONValue 接住再按候选键提取。HTTP 200 本身不证明
/// ready；全部候选缺失时返回 unknown，不许把未知压成
/// 未就绪。raw 只供客户端内诊断与后续字段冻结，不上屏。
/// 注意语义边界：该端点描述的是桌面 computer-use 就绪
/// 态，不必然等同「浏览器任务能力」——浏览器段只把它
/// 作留口状态行，文案不扩写成任务能力承诺（§6.5）。
public struct ComputerUseStatus: Decodable, Sendable, Equatable {
    public let readiness: ComputerUseReadiness
    public let raw: [String: JSONValue]

    public init(readiness: ComputerUseReadiness, raw: [String: JSONValue]) {
        self.readiness = readiness
        self.raw = raw
    }

    private static let boolKeys = ["ready", "is_ready", "available"]
    private static let stringKeys = ["status", "state", "readiness"]
    private static let nestKeys = ["computer_use", "permissions", "status"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(JSONValue.self)
        guard case .object(let object) = value else {
            readiness = .unknown
            raw = [:]
            return
        }
        raw = object
        readiness = Self.extract(from: object, depth: 0)
    }

    /// 候选提取：顶层及最多两层嵌套（只进 computer_use/
    /// permissions/status 三类对象键，不全树盲搜同名字段，
    /// 避免把子工具的 ready 误当整体就绪）
    static func extract(
        from object: [String: JSONValue], depth: Int
    ) -> ComputerUseReadiness {
        for key in boolKeys {
            if case .bool(let flag)? = object[key] {
                return flag ? .ready : .notReady
            }
        }
        for key in stringKeys {
            if let text = object[key]?.stringValue {
                switch text.lowercased() {
                case "ready", "available", "ok":
                    return .ready
                case "not_ready", "unavailable", "disabled", "needs_permission":
                    return .notReady
                default:
                    break
                }
            }
        }
        guard depth < 2 else { return .unknown }
        for key in nestKeys {
            if case .object(let nested)? = object[key] {
                let found = extract(from: nested, depth: depth + 1)
                if found != .unknown { return found }
            }
        }
        return .unknown
    }
}

/// 浏览器段状态机已于 0.9.0（P2）迁往盒桥口径
/// （BoxBridgeHubState，见 BoxBridgeModels）：原
/// BrowserHubState 读的是 9119 computer-use 错位源
/// （本机桌面自动化、恒未就绪），就此退役；
/// ComputerUseStatus 本体保留，供设置详情如实标注
/// 本机桌面自动化状态，不再冒充浏览器状态。

/// 浏览器任务保留模型（边界定义，不参与 v1 解码）：
/// 后端任务记录接口定稿前不接任何数据源，尤其不能从
/// 会话 timeline 的 prompt metadata 拼凑——那条路没有
/// 缩略图、没有稳定任务边界，做出来会冒充任务列表。
public struct BrowserTaskSummary: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let domain: String
    public let startedAt: Date?
    public let endedAt: Date?
    public let thumbnailURL: URL?

    public init(
        id: String, title: String, domain: String,
        startedAt: Date?, endedAt: Date?, thumbnailURL: URL?
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.thumbnailURL = thumbnailURL
    }
}
