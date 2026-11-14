import Foundation

// MARK: - 符号动效登记册（动效规矩包，DESIGN-V4 §245.1）
//
// 治理口径（用户 2026-11-08 动态图标三条规矩＋位置
// 白名单，与动效宪法 M1/M5 并行）：
// 1. 两种状态来回切 → 变形图标（原生 symbolEffect
//    形变等价实现，Morph 路线①）；
// 2. 一次性操作反馈 → 动态图标（LORD 类位置；本体
//    未落前以原生形变占位落点，逐项在册注明）；
// 3. 会动的图标只给最常点的位置——白名单外一律静态
//    SF Symbols，新增接入点先入本册、后落码。
//
// 执行形态：本册是全仓符号动效接入点的唯一账本。
// CI 静态核查（Scripts/ci/check_symbol_motion.py）逐
// 处比对源码 symbolEffect/Lottie 接入点与本册条目
// （按文件计条），未登记接入点或条目过期即判红。
// 条目格式被脚本正则解析，字段名与一行一条的排版
// 不许改形。
//
// 白名单未落项（无代码接入点、不入下表，账在
// §245.1）：侧栏开↔关变形、消息语音播放↔暂停变形、
// LORD 本体（点赞/收藏成功/连接成功，lottie 依赖与
// JSON 资产均未落；署名行已在设置页 Icons by
// Lordicon）。

/// 符号动效接入点类别
public enum SymbolMotionKind: Sendable {
    /// 两状态形变（规矩 1：发送↔停止类）
    case morphReplace
    /// 一次性反馈位置的原生形变占位（规矩 2 位置）
    case feedbackReplace
    /// 状态指示形变（展开/收起 chevron 类）
    case stateIndicator
}

/// 登记状态
public enum SymbolMotionStatus: Sendable {
    /// 白名单内、现行有效
    case registered
    /// 白名单外存量：已入账待裁，不许扩散、待 UI 批
    /// 或用户裁决去留
    case legacyPendingRuling
}

/// 一条登记＝一个真实代码接入点
public struct SymbolMotionSite: Sendable {
    public let id: String
    public let file: String
    public let component: String
    public let kind: SymbolMotionKind
    public let status: SymbolMotionStatus
    /// Reduce Motion 降级形态（动效宪法 M8）
    public let reduceMotion: String
}

public enum SymbolMotionRegistry {
    public static let sites: [SymbolMotionSite] = [
        SymbolMotionSite(
            id: "SM-1",
            file: "Sources/OneDayApp/ChatView.swift",
            component: "发送舱圆盘键 发送↑↔停止■",
            kind: .morphReplace,
            status: .registered,
            reduceMotion: "系统符号过渡自理（平台行为）"
        ),
        SymbolMotionSite(
            id: "SM-2",
            file: "Sources/OneDayDesign/Components.swift",
            component: "CopyButton 复制 doc.on.doc↔对勾（§14 条 10，2.5 秒自隐）",
            kind: .feedbackReplace,
            status: .registered,
            reduceMotion: "系统符号过渡自理（平台行为）"
        ),
        SymbolMotionSite(
            id: "SM-3",
            file: "Sources/OneDayApp/ReasoningBlock.swift",
            component: "思考块展开/收起 chevron 上下翻转",
            kind: .stateIndicator,
            status: .legacyPendingRuling,
            reduceMotion: "Reduce Motion 时瞬时切换（组件头注在案）"
        ),
    ]
}
