#if os(iOS)
// Mac 地基棒平台守卫：Live Activity 是 iOS 专属能力（对位表第 92 件，Mac 以菜单栏状态项等价），macOS 编译排除；iOS 侧内容一字未动。
import ActivityKit
import Foundation

/// 实时活动属性（总表 163，DESIGN §385.3）：App 与
/// widget 扩展共用一型（两目标同依赖 OneDayCore，
/// 属性定义只此一份）。隐私口径钉死在本型形状上：
/// 静态属性只有任务名、内容态只有进度阶段与阶段起
/// 始时刻——不设正文字段、不设回复片段字段，锁屏
/// 可见面从类型层就没有正文可呈。
public struct RunLiveActivityAttributes: ActivityAttributes {

    /// 进度阶段（两档：起跑未出字＝准备中、流式出
    /// 字中＝生成中）
    public enum Phase: String, Codable, Equatable, Sendable {
        case preparing
        case generating

        public func label(locale: Locale = AppLocale.uiLocale) -> String {
            switch self {
            case .preparing: return L10n.string("准备中", locale: locale)
            case .generating: return L10n.string("生成中", locale: locale)
            }
        }
    }

    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: Phase
        /// 阶段起始时刻（呈现侧算已持续时长用）
        public var phaseStartedAt: Date

        public init(phase: Phase, phaseStartedAt: Date) {
            self.phase = phase
            self.phaseStartedAt = phaseStartedAt
        }
    }

    /// 任务名（会话标题；起跑沿由 App 侧截断后写入，
    /// 见 RunLiveActivityCenter 的截断口径）
    public var taskName: String

    public init(taskName: String) {
        self.taskName = taskName
    }
}

#endif
