import Foundation

/// 能力协商单源（总表 157，DESIGN §394）：把「服务端
/// 广告了什么、探针探到了什么」翻成逐项产品能力的三
/// 态结论——功能面按此降级而非报错。此前能力判定只
/// 活在自检面的呈现合成里（SelfCheckReportBuilder 与
/// 注册表口径手工同构、双口径隐患），且功能面零消费。
/// 本枚举是判定单源：输入只有真回读（/v1/capabilities
/// 的 features 与只读路由探针），没证据一律 unknown、
/// 不往好处猜（僵尸禁令）。
///
/// 逐项与 hermes-deploy CAPABILITIES.md 注册表对位：
/// 只收编有确定性只读判据的项——#1 认领/#2 反应写入
/// 走路由探针、#4 任务幂等/#14 消息级幂等走 features
/// 旗标；#3 反应投影只有行为探针可知、#9 rewind 无
/// 只读探针、#6/#7/#8 属伴生面（ServiceHealth 域），
/// 均不在本账内假判，分工见 §394。版本地板（minApp-
/// Version/apiLevel 区间）归 G-18（§387.5 定版口径：
/// 发布单点＝伴生 info、连接流硬门），本账只管功能级。
public enum CapabilityAvailability: Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

public struct NegotiatedCapability: Equatable, Sendable, Identifiable {
    /// 注册表对位 id（与 CAPABILITIES.md 条目同名）
    public let id: String
    public let title: String
    public let availability: CapabilityAvailability
    /// unavailable 时 OneDay 的预期表现（人话，逐项对
    /// 注册表「缺失时 OneDay 的预期表现」列提炼）；
    /// 其余态 nil 不占位
    public let absenceText: String?

    public init(
        id: String, title: String,
        availability: CapabilityAvailability,
        absenceText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.availability = availability
        self.absenceText = availability == .unavailable
            ? absenceText
            : nil
    }
}

public enum CapabilityNegotiation {

    // MARK: - 逐项判定（单源原语，自检合成与功能面共用）

    /// #1 设备配对认领：GET 打 claim 路由，405＝在位、
    /// 404＝不在位，其余回码无法确认
    public static func enrollmentAvailability(
        _ probe: RouteProbeResult?
    ) -> CapabilityAvailability {
        guard let probe else { return .unknown }
        switch probe.status {
        case 405: return .available
        case 404: return .unavailable
        default: return .unknown
        }
    }

    /// #2 消息反应写入：405/200＝在位；404 且错误码
    /// message_not_found 是「路由在位、目标消息不存
    /// 在」的实证（CAPABILITIES 探针法明载），同判在位
    public static func reactionsAvailability(
        _ probe: RouteProbeResult?
    ) -> CapabilityAvailability {
        guard let probe else { return .unknown }
        switch probe.status {
        case 405, 200: return .available
        case 404:
            return probe.errorCode == "message_not_found"
                ? .available
                : .unavailable
        default: return .unknown
        }
    }

    /// #4 任务幂等（Idempotency-Key，上游自带）：
    /// features.runs_idempotency.supported 对象型旗标
    public static func runIdempotencyAvailability(
        _ capabilities: CapabilitiesResponse?
    ) -> CapabilityAvailability {
        guard let supported = capabilities?.runsIdempotencySupported
        else { return .unknown }
        return supported ? .available : .unavailable
    }

    /// #14 消息级幂等（client_message_id，部署包 1.5.0
    /// 已入包待应用）：features.runs_idempotency 对象
    /// 内的 client_message_id 子旗标；能力面已取到而子
    /// 旗标缺失/为假＝服务端未发布此能力（非未知）
    public static func clientMessageIdAvailability(
        _ capabilities: CapabilitiesResponse?
    ) -> CapabilityAvailability {
        guard let capabilities else { return .unknown }
        return capabilities.clientMessageIdSupported == true
            ? .available
            : .unavailable
    }

    /// #22 选择框（部署包 1.12.0 占位，总表 203）：
    /// features.options_card 布尔旗标；能力面已取到
    /// 而旗标缺失/为假＝服务端未发布此能力（非未知）
    public static func optionsCardAvailability(
        _ capabilities: CapabilitiesResponse?
    ) -> CapabilityAvailability {
        guard let capabilities else { return .unknown }
        return capabilities.optionsCardSupported == true
            ? .available
            : .unavailable
    }

    /// #21 设置注册表（AI 自主设置权一期，DESIGN
    /// §437）：features.settings_registry 布尔旗标——
    /// 亮＝设置面按注册表渲染、假＝服务端未发布此能
    /// 力（回落内置目录，非未知）；能力面没取到/旗标
    /// 缺失＝unknown，消费方同按回落处理（行为不变）
    public static func settingsRegistryAvailability(
        _ capabilities: CapabilitiesResponse?
    ) -> CapabilityAvailability {
        guard let flag = capabilities?.featureFlag("settings_registry")
        else { return .unknown }
        return flag ? .available : .unavailable
    }

    /// #19 AI 自反应（部署包 1.8.0，DESIGN §432）：
    /// features.self_reactions 布尔旗标；能力面已
    /// 取到而旗标缺失/为假＝服务端未发布此能力
    /// （非未知），与 #14 同口径
    public static func selfReactionsAvailability(
        _ capabilities: CapabilitiesResponse?
    ) -> CapabilityAvailability {
        guard let capabilities else { return .unknown }
        return capabilities.selfReactionsSupported == true
            ? .available
            : .unavailable
    }

    // MARK: - 整表合成

    /// 本账四项的整表结论（注册表序）
    public static func verdicts(
        capabilities: CapabilitiesResponse?,
        enrollmentProbe: RouteProbeResult?,
        reactionsProbe: RouteProbeResult?
    ) -> [NegotiatedCapability] {
        [
            NegotiatedCapability(
                id: "enrollment", title: "设备配对认领",
                availability: enrollmentAvailability(enrollmentProbe),
                absenceText: "扫码配对不可用，退回手填连接信息"
            ),
            NegotiatedCapability(
                id: "reactionsWrite", title: "消息反应写入",
                availability: reactionsAvailability(reactionsProbe),
                absenceText: "反应只在本机显示、服务端不落库，刷新即丢"
            ),
            NegotiatedCapability(
                id: "runIdempotency", title: "任务幂等",
                availability: runIdempotencyAvailability(capabilities),
                absenceText: "断网重发可能重复执行同一轮，出现双份回复"
            ),
            NegotiatedCapability(
                id: "optionsCard", title: "选择框",
                availability: optionsCardAvailability(capabilities),
                absenceText: "提问轮不带可点选选项，只能打字作答"
            ),
            NegotiatedCapability(
                id: "clientMessageId", title: "消息级幂等",
                availability: clientMessageIdAvailability(capabilities),
                absenceText: "跨轮重发去重不成立，提交段未确认的发送只许手动处理"
            ),
        ]
    }

    public static func verdict(
        id: String, in verdicts: [NegotiatedCapability]
    ) -> NegotiatedCapability? {
        verdicts.first { $0.id == id }
    }
}
