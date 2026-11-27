import Foundation

/// 中枢分格注册表（DESIGN §434，用户 2026-11-24
/// 01:03 亲裁「分格本身不许写死」）：格集不再由
/// 视图层硬编码枚举决定，而是由本注册表按真回读
/// 输入裁决——有真能力才长格、没有就不长；日后
/// 新能力建成并广告能力位后，AI 只需在输入侧接上
/// 对应旗标即可加格，不用改格集代码、不用发新版
/// App 改枚举。本注册表与 §435 自主设置权课题同
/// 源（同一能力注册表：服务端 GET /v1/capabilities
/// 回读为正源，部署包 CAPABILITIES.md 为服务端半
/// 本），§435 落档时两处互引对接。
///
/// 顺序照参照大头态分段胶囊实测序：工作／审核／
/// 电脑／身份／邮箱（过滤后保持相对序）。
public enum HubSegmentID: String, CaseIterable, Identifiable, Sendable {
    case work
    case audit
    case computer
    case identity
    case mail

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: return "工作"
        case .audit: return "审核"
        case .computer: return "电脑"
        case .identity: return "身份"
        case .mail: return "邮箱"
        }
    }

    public var systemImage: String {
        switch self {
        case .work: return "list.bullet"
        case .audit: return "shield"
        case .computer: return "display"
        case .identity: return "touchid"
        case .mail: return "envelope"
        }
    }
}

/// 注册表输入（判定单源纪律同 CapabilityNegotia-
/// tion：只收真回读/真状态，没证据按否处理，不
/// 往好处猜——僵尸禁令）。
public struct HubSegmentInputs: Equatable, Sendable {
    /// 枢纽已连通（共享 store 就绪）：未连通时一格
    /// 不长，呈现层只显加载/断连态
    public var connected: Bool
    /// 授权账本回读成功（GET /v1/grants，能力 #12
    /// 的活证：端点在位且清单读回）
    public var grantsReadbackOK: Bool
    /// 审批账可用（待批聚合回读就绪，能力 #10）
    public var approvalsReadbackOK: Bool
    /// 云电脑通道在位（Box 钥匙在本机钥匙串——
    /// Box 是第三方直连通道、不经 Hermes 能力位，
    /// 其注册输入为本地通道状态，如实区别）
    public var boxConfigured: Bool
    /// 邮件列表数据源可用；只有端点真实可读后才长格。
    public var mailDataSourceAvailable: Bool

    public init(
        connected: Bool,
        grantsReadbackOK: Bool,
        approvalsReadbackOK: Bool,
        boxConfigured: Bool,
        mailDataSourceAvailable: Bool
    ) {
        self.connected = connected
        self.grantsReadbackOK = grantsReadbackOK
        self.approvalsReadbackOK = approvalsReadbackOK
        self.boxConfigured = boxConfigured
        self.mailDataSourceAvailable = mailDataSourceAvailable
    }

    /// 未连通缺省（呈现层任务回读前的初值）
    public static let disconnected = HubSegmentInputs(
        connected: false,
        grantsReadbackOK: false,
        approvalsReadbackOK: false,
        boxConfigured: false,
        mailDataSourceAvailable: false
    )
}

public enum HubSegmentRegistry {
    /// 格集裁决（纯函数，钉测单源）：锚格＝工作＋
    /// 身份（随连通在位——台账与人设是枢纽的底
    /// 盘，两面各自有断源降级态、格本身不假）；
    /// 审核格须授权账本或审批账任一回读成功；
    /// 电脑格须 Box 通道在位；邮箱格须邮件列表数
    /// 据源已由能力回读取证。输出恒按 HubSegmentID 声明序
    /// （＝参照胶囊序）。
    public static func resolve(
        _ inputs: HubSegmentInputs
    ) -> [HubSegmentID] {
        guard inputs.connected else { return [] }
        return HubSegmentID.allCases.filter { segment in
            switch segment {
            case .work, .identity:
                return true
            case .audit:
                return inputs.grantsReadbackOK
                    || inputs.approvalsReadbackOK
            case .computer:
                return inputs.boxConfigured
            case .mail:
                return inputs.mailDataSourceAvailable
            }
        }
    }
}
