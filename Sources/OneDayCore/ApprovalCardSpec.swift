import Foundation

/// 审批卡钮形态角色（D10 定版④）：三档层级只
/// 许在此定——批准填充主钮、总是允许描边次钮、
/// 驳回文字级；视图层只消费角色、不自拼形态
public enum ApprovalCardButtonRole: Sendable {
    case filledPrimary
    case outlinedSecondary
    case text
}

/// 审批卡三档裁决动作（样式二期 S2-01/S2-03）：枚举
/// 次序即钮栈自上而下的次序——批准（主）／总是允许
/// 这一类／驳回。聊天就地卡与枢纽待批卡共用同一卡面
/// 组件，动作集、次序与主次角色只许在此处定，视图层
/// 不许各拼各的（两面同脸的语义真源）。
public enum ApprovalCardAction: String, CaseIterable, Sendable {
    case approve
    case alwaysAllow
    case reject

    /// 主次角色：主钮恒一只（批准）——主钮的
    /// 「满」靠填充与色，不靠宽度（旧形态三钮 hug
    /// 内容宽、居中飘，主次只剩深浅，S2-01）；非
    /// 主两档的形态分工见 buttonRole（D10 定版④）
    public var isPrimary: Bool { self == .approve }

    /// 钮形态角色（D10 定版④单源）：批准＝填充
    /// 主钮／总是允许＝描边次钮／驳回＝文字级
    public var buttonRole: ApprovalCardButtonRole {
        switch self {
        case .approve: return .filledPrimary
        case .alwaysAllow: return .outlinedSecondary
        case .reject: return .text
        }
    }

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
    /// 裁决钮高（通栏胶囊档：填充主钮与描边次
    /// 钮同高；文字级驳回走 textButtonHeight）
    public static let buttonHeight: CGFloat = 48
    /// 裁决钮纵距
    public static let buttonSpacing: CGFloat = 10
    /// 文字级钮高（D10 定版④）：驳回无填充、只
    /// 占一行文字高，不占胶囊 48——行高合成经
    /// actionStackHeight 同读此值，视图层不许
    /// 另给数
    public static let textButtonHeight: CGFloat = 36

    /// 动作栈：可裁决才有栈且恒为三档全栈；不可裁决
    /// 零钮——卡面只留说明与去向，不摆假按钮（审批
    /// 规格 §5 枚举定案，与 canDecide 同口径）
    public static func actionStack(
        canDecide: Bool
    ) -> [ApprovalCardAction] {
        actionStack(canDecide: canDecide, blocked: false)
    }

    /// 动作栈（§245 防呆）：记录被桥侧预检判定确定
    /// 性批不了（blocked）时只留驳回一档——批准与总
    /// 是允许（＝立即批准＋立规则）都必败，不许摆出
    /// 来让用户白点；驳回是这类死单唯一的出路（伴
    /// 生 APPROVAL-DECIDE-FAIL-REPORT 待修项口径）
    public static func actionStack(
        canDecide: Bool, blocked: Bool
    ) -> [ApprovalCardAction] {
        actionStack(
            canDecide: canDecide, blocked: blocked, highRisk: false
        )
    }

    /// 动作栈（高风险写操作降两钮）：高风险写操作只给
    /// 「允许／拒绝」，不提供「总是允许」
    public static func actionStack(
        canDecide: Bool, blocked: Bool, highRisk: Bool
    ) -> [ApprovalCardAction] {
        guard canDecide else { return [] }
        if blocked { return [.reject] }
        if highRisk { return [.approve, .reject] }
        return ApprovalCardAction.allCases
    }

    /// 单钮高（按形态角色）：胶囊档（填充/描
    /// 边）＝buttonHeight、文字级＝
    /// textButtonHeight
    public static func buttonHeight(
        for action: ApprovalCardAction
    ) -> CGFloat {
        action.buttonRole == .text
            ? textButtonHeight : buttonHeight
    }

    /// 钮栈总高（行高合成单读口）：各钮高之和
    /// ＋钮间纵距；空栈＝0
    public static func actionStackHeight(
        _ actions: [ApprovalCardAction]
    ) -> CGFloat {
        guard !actions.isEmpty else { return 0 }
        return actions.reduce(0) {
            $0 + buttonHeight(for: $1)
        } + buttonSpacing * CGFloat(actions.count - 1)
    }

    /// 卡面工具图标（§245，对标 Muse 审批卡的
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

/// 审批区队列派生（D10 定版②「一次只活一张＋还
/// 有 N 件待批」）：流末区活卡恒为未锚待批按桥序
/// 的第一条，其余收纳成一行计数。纯派生、不持状
/// 态——裁决落定后第一条移出、下一条自然顶上，
/// 与既有刷新/对账同拍，不需要队列状态机。视图
/// 渲染、行高合成、facet 摘要三处只许经此派生
/// 取活卡与余数（§329–§331 备忘体系同型事故防
/// 线：三处口径漏一处即裁剪/跳高）。
///
/// 锚定行豁免登记（主线裁定）：已落锚记录由其锚
/// 定行自承载（§165 四态），不进本队列的「只活
/// 一张」口径——derive 先按锚定集排除，锚定卡
/// 的存灭不影响流末区活卡位。
public struct ApprovalZoneQueue: Equatable, Sendable {
    /// 当前活卡的记录 id；无未锚待批时为 nil
    public let activeRecordID: String?
    /// 收纳进计数行的件数（未锚待批去掉活卡后
    /// 的余数）；计数行仅在 ≥1 时在席
    public let queuedCount: Int

    /// 未锚待批总数（活卡 0/1＋收纳数）：行高
    /// 备忘键须含此数——计数行在席与否随总数
    /// 变，键不含计数会留旧高
    public var pendingCount: Int {
        (activeRecordID == nil ? 0 : 1) + queuedCount
    }

    /// 派生：recordIDs 为桥序全量待批 id，
    /// anchoredIDs 为已落锚排除集
    public static func derive(
        recordIDs: [String], anchoredIDs: Set<String>
    ) -> ApprovalZoneQueue {
        let unanchored = recordIDs.filter {
            !anchoredIDs.contains($0)
        }
        return ApprovalZoneQueue(
            activeRecordID: unanchored.first,
            queuedCount: max(0, unanchored.count - 1)
        )
    }
}
