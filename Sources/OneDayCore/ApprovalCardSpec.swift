import Foundation

/// 审批卡三档裁决动作（样式二期 S2-01/S2-03）：枚举
/// 次序即钮栈自上而下的次序——批准（主）／总是允许
/// 这一类／驳回。聊天就地卡与枢纽待批卡共用同一卡面
/// 组件，动作集、次序与主次角色只许在此处定，视图层
/// 不许各拼各的（两面同脸的语义真源）。
public enum ApprovalCardAction: String, CaseIterable, Sendable {
    case approve
    case alwaysAllow
    case reject

    /// 主次角色：主钮恒一只（批准），余皆次钮——主钮
    /// 的「满」靠填充与色，不靠宽度（旧形态三钮 hug
    /// 内容宽、居中飘，主次只剩深浅，S2-01）
    public var isPrimary: Bool { self == .approve }

    /// 钮面文案（目录取词，与既有确认弹窗口径一致）
    public func title(
        locale: Locale = AppLocale.uiLocale
    ) -> String {
        switch self {
        case .approve:
            return L10n.string("批准", locale: locale)
        case .alwaysAllow:
            return L10n.string("总是允许这一类", locale: locale)
        case .reject:
            return L10n.string("驳回", locale: locale)
        }
    }
}

/// 审批卡动作栈规格：几何落值与栈的构成判定。
/// 几何口径：参照 Muse 审批卡真机量测（钮高约
/// 50pt、钮间纵距约 10pt，审计 style-audit-2 S2-01），
/// 落值钮高 48。数值由 ApprovalCardSpecTests 钉住。
public enum ApprovalCardSpec {
    /// 裁决钮高（通栏胶囊，三钮同高）
    public static let buttonHeight: CGFloat = 48
    /// 裁决钮纵距
    public static let buttonSpacing: CGFloat = 10

    /// 动作栈：可裁决才有栈且恒为三档全栈；不可裁决
    /// 零钮——卡面只留说明与去向，不摆假按钮（审批
    /// 规格 §5 枚举定案，与 canDecide 同口径）
    public static func actionStack(
        canDecide: Bool
    ) -> [ApprovalCardAction] {
        actionStack(canDecide: canDecide, blocked: false)
    }

    /// 动作栈（§234 防呆）：记录被桥侧预检判定确定
    /// 性批不了（blocked）时只留驳回一档——批准与总
    /// 是允许（＝立即批准＋立规则）都必败，不许摆出
    /// 来让用户白点；驳回是这类死单唯一的出路（伴
    /// 生 APPROVAL-DECIDE-FAIL-REPORT 待修项口径）
    public static func actionStack(
        canDecide: Bool, blocked: Bool
    ) -> [ApprovalCardAction] {
        guard canDecide else { return [] }
        if blocked { return [.reject] }
        return ApprovalCardAction.allCases
    }

    /// 卡面工具图标（§234，对标 Muse 审批卡的
    /// 工具图标位）：按子系统取既有全 App 同名符号
    /// （记忆＝brain、技能＝puzzlepiece.extension，
    /// 与记忆面/配置面同源，不新造图）；未知类型走
    /// 通用问号圈
    public static func toolIconName(
        for subsystem: WriteGateSubsystem
    ) -> String {
        switch subsystem {
        case .memory: return "brain"
        case .skills: return "puzzlepiece.extension"
        case .unknown: return "questionmark.circle"
        }
    }
}
