import Foundation

/// 活头像（§479，规格 living-avatar-spec-20261124.md）：
/// 状态词表＋状态机＋工具族分类＋片段目录解析，全在
/// Core 单点、纯值类型＋注入时钟，可单测。状态机只
/// 吃既有 runs 事件流的语义转译（喂食点在 App 侧
/// ChatView.followRunEvents，与 liveActivityPhrase
/// 同位），自己不开任何通道；呈现（播哪段/静态兜
/// 底）由目录解析器按「状态×明暗×当前头像绑定」裁
/// 决，播放器只消费裁决结果，不许自带第二套状态。

// MARK: - 工具族（规格 §1.2：按工具名归族，分不了不猜）

public enum LivingToolFamily: String, Sendable, Equatable {
    case write
    case search
    case execute
    case delegate
    case general
}

/// 工具名→族映射（规格 §1.2）：名单逐名列明——
/// 主体取自 App 既有分类表 ToolCards.swift 实见的
/// 工具名，另加 Hermes 网关规范名（search_files/
/// web_extract/process/delegate_task，事件流自网关
/// 来、名以网关为准）；映射缺失一律 .general，不
/// 按名字像什么硬猜。服务端工具集增减时只改此表。
public enum LivingToolFamilyClassifier {
    public static func classify(toolName: String) -> LivingToolFamily {
        switch toolName {
        case "write_file", "files_write", "patch",
             "calendar_create_event", "calendar_update_event",
             "reminders_create", "reminders_complete",
             "clipboard_set", "media_playlist_create",
             "alarm_set", "alarm_cancel",
             "compose_email", "compose_sms":
            return .write
        case "read_file", "files_read", "files_list",
             "search_files", "web_search", "web_extract",
             "browser_snapshot", "browser_get_content",
             "contacts_search", "location_search_places",
             "location_geocode", "location_current",
             "media_library_search", "tool_search",
             "tool_describe", "vision_analyze", "vision_ocr",
             "vision_scan_code", "vision_document_scan",
             "device_status", "device_info", "box_status",
             "box_list", "home_status", "calendar_list_events",
             "reminders_list", "alarm_list", "clipboard_get",
             "file_preview", "health_daily_summary":
            return .search
        case "terminal", "execute_code", "shell", "process",
             "computer_act", "browser_navigate", "browser_click",
             "browser_type", "browser_back", "browser_forward",
             "browser_reload", "shortcut_run",
             "ondevice_model_run", "camera_capture",
             "media_playback_control", "open_target",
             "file_print", "call_start":
            return .execute
        case "delegate_task":
            return .delegate
        default:
            return .general
        }
    }
}

// MARK: - 状态词表（规格 §1/§7，两包共用词表）

public enum LivingAvatarState: Sendable, Equatable {
    case idle
    case listening
    case thinking
    case working(LivingToolFamily)
    case speaking
    case done
    case blocked
    case awaiting
    case asleep
    case waking

    /// 状态键（与规格命名逐字一致；working 的族
    /// 只决定片段变体、不进状态键）
    public var key: String {
        switch self {
        case .idle: return "idle"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .working: return "working"
        case .speaking: return "speaking"
        case .done: return "done"
        case .blocked: return "blocked"
        case .awaiting: return "awaiting"
        case .asleep: return "asleep"
        case .waking: return "waking"
        }
    }
}

/// 状态机喂食事件：既有 runs 事件流的语义转译
/// （App 侧转译点与事件原名对照见 ChatView 接线）
public enum LivingAvatarEvent: Sendable, Equatable {
    case runStarted
    case reasoning
    case toolStarted(LivingToolFamily)
    case toolCompleted(
        family: LivingToolFamily, failed: Bool
    )
    case textDelta
    case terminalCompleted
    case terminalFailed
    case terminalCancelled
    case streamLost
    case interaction
}

// MARK: - 状态机（规格 §1.3 映射＋优先级）

public struct LivingAvatarStateMachine: Sendable {
    /// 瞬时呈示窗（秒）：完成/醒来短播即回落（规格
    /// §1.3 S6＝2–3 秒定版取 2.8）
    public static let doneWindow: TimeInterval = 2.8
    public static let wakeWindow: TimeInterval = 2.8
    /// 工具级失败的 blocked 短置窗：其间任一后续
    /// 活动事件即清（run 已续走就不许还挂着错态）
    public static let toolBlockedWindow: TimeInterval = 3
    /// run 级失败的 blocked 置窗（规格 S7 退出规
    /// 则：新交互/新 run 即清、无交互 10 秒回落）
    public static let runBlockedWindow: TimeInterval = 10
    /// 睡眠阈值（规格默认 30 分钟；注册表键服务
    /// 端侧后续接，本期常量、DESIGN §479.4 登记）
    public var sleepThreshold: TimeInterval = 1800

    public private(set) var lastActivityAt: Date
    private var runActive = false
    private var toolStack: [LivingToolFamily] = []
    private var streamingText = false
    private var blockedUntil: Date?
    private var doneUntil: Date?
    private var wakeUntil: Date?

    public init(startedAt: Date) {
        lastActivityAt = startedAt
    }

    public mutating func handle(
        _ event: LivingAvatarEvent, at now: Date
    ) {
        switch event {
        case .runStarted:
            blockedUntil = nil
            doneUntil = nil
            wakeUntil = nil
            runActive = true
            toolStack = []
            streamingText = false
            lastActivityAt = now
        case .reasoning, .textDelta:
            // 活动即清工具级错态（run 还在往前走）
            blockedUntil = nil
            if event == .textDelta { streamingText = true }
            lastActivityAt = now
        case .toolStarted(let family):
            blockedUntil = nil
            toolStack.append(family)
            streamingText = false
            lastActivityAt = now
        case .toolCompleted(let family, let failed):
            // 按族摘除（并行工具乱序完成不串位）；
            // 族不在栈内时摘栈尾兜底，不许栈泄漏
            if let index = toolStack.lastIndex(of: family) {
                toolStack.remove(at: index)
            } else if !toolStack.isEmpty {
                toolStack.removeLast()
            }
            if failed {
                blockedUntil = now + Self.toolBlockedWindow
            }
            lastActivityAt = now
        case .terminalCompleted:
            runActive = false
            toolStack = []
            streamingText = false
            doneUntil = now + Self.doneWindow
            lastActivityAt = now
        case .terminalFailed:
            runActive = false
            toolStack = []
            streamingText = false
            blockedUntil = now + Self.runBlockedWindow
            lastActivityAt = now
        case .terminalCancelled, .streamLost:
            // 取消/结果未知都不算成败（§58 既定口
            // 径）：直接回未活动，不置任何瞬时态
            runActive = false
            toolStack = []
            streamingText = false
            lastActivityAt = now
        case .interaction:
            // 睡着时被交互唤醒：先记醒来瞬时态（无
            // run 接管时才呈示得出来，见优先级）
            if state(at: now) == .asleep {
                wakeUntil = now + Self.wakeWindow
            }
            blockedUntil = nil
            lastActivityAt = now
        }
    }

    /// 当前状态（优先级，规格 §1.3＋§479.4）：
    /// blocked ＞ 运行态（working＞speaking＞
    /// thinking）＞ waking ＞ done ＞ asleep ＞ idle。
    /// awaiting/listening 一期无喂食源、机器不产出
    /// （词表与呈现兜底在册，不假装有源）。
    public func state(at now: Date) -> LivingAvatarState {
        if let blockedUntil, now < blockedUntil {
            return .blocked
        }
        if runActive {
            if let family = toolStack.last {
                return .working(family)
            }
            if streamingText { return .speaking }
            return .thinking
        }
        if let wakeUntil, now < wakeUntil {
            return .waking
        }
        if let doneUntil, now < doneUntil {
            return .done
        }
        if now.timeIntervalSince(lastActivityAt)
            >= sleepThreshold {
            return .asleep
        }
        return .idle
    }

    /// 下一个纯时间驱动的状态变化点（供 App 侧定
    /// 时器精确唤醒，不许轮询猜）：无则 nil
    public func nextTransitionDate(
        after now: Date
    ) -> Date? {
        var candidates: [Date] = []
        if let blockedUntil, blockedUntil > now {
            candidates.append(blockedUntil)
        }
        if let wakeUntil, wakeUntil > now {
            candidates.append(wakeUntil)
        }
        if let doneUntil, doneUntil > now {
            candidates.append(doneUntil)
        }
        if !runActive {
            let sleepAt = lastActivityAt.addingTimeInterval(
                sleepThreshold
            )
            if sleepAt > now { candidates.append(sleepAt) }
        }
        return candidates.min()
    }
}

// MARK: - 片段目录（manifest schema living-avatar-clips/1）

/// 明暗外观（App 侧由 colorScheme 映射进来）
public enum LivingAppearance: Sendable, Equatable {
    case light
    case dark
}

public enum LivingClipFallback: String, Sendable, Equatable {
    /// 该状态本就无片段（规格/试验套缺口）
    case noClipForState
    /// 该状态有片段但当前明暗档缺位（如醒来仅深色）
    case appearanceMissing
    /// 当前头像条目不是片段绑定条目（换图即整套 stale）
    case avatarMismatch
    /// 目录缺失/解析失败
    case catalogMissing
}

public enum LivingClipResolution: Sendable, Equatable {
    case clip(fileName: String, transient: Bool)
    case staticImage(LivingClipFallback)
}

/// 片段目录：解析服务端同形 manifest（schema
/// living-avatar-clips/1），按状态×明暗×绑定裁决
/// 呈现。绑定口径代行规格 bound_version：片段只
/// 对 manifest 的 bound_avatar.id 那个条目生效，
/// 当前条目非它即整套回落静态（新脸不播旧动作）。
public struct LivingAvatarCatalog: Sendable {
    public let boundAvatarID: String?

    private struct StateEntry: Sendable {
        var file: String?
        var dark: String?
        var callLight: String?
        var callDark: String?
    }

    private var entries: [String: StateEntry] = [:]

    /// manifest 原始 JSON 解析；形状不对回 nil
    /// （调用方按 catalogMissing 全静态，不崩）
    public init?(manifestData: Data) {
        guard let object = try? JSONSerialization
            .jsonObject(with: manifestData),
              let root = object as? [String: Any]
        else { return nil }
        if let bound = root["bound_avatar"]
            as? [String: Any] {
            boundAvatarID = bound["id"] as? String
        } else {
            boundAvatarID = nil
        }
        guard let states = root["states"]
            as? [String: Any] else { return nil }
        for (key, raw) in states {
            guard let dict = raw as? [String: Any]
            else { continue }
            var entry = StateEntry(
                file: dict["file"] as? String,
                dark: dict["dark"] as? String
            )
            if let call = dict["call"] as? [String: Any] {
                entry.callLight = call["light"] as? String
                entry.callDark = call["dark"] as? String
            }
            entries[key] = entry
        }
    }

    private func pick(
        _ entry: StateEntry?, appearance: LivingAppearance
    ) -> String? {
        guard let entry else { return nil }
        switch appearance {
        case .dark: return entry.dark ?? entry.file
        case .light: return entry.file
        }
    }

    /// 状态呈现裁决（兜底表 DESIGN §479.5 逐行对位）
    public func resolve(
        state: LivingAvatarState,
        appearance: LivingAppearance,
        currentAvatarItemID: String?
    ) -> LivingClipResolution {
        guard let boundAvatarID,
              currentAvatarItemID == boundAvatarID
        else { return .staticImage(.avatarMismatch) }
        switch state {
        case .idle:
            return clipOrFallback("S1_idle", appearance)
        case .working(.write):
            if let found = pick(
                entries["S4_working_write"],
                appearance: appearance
            ) {
                return .clip(fileName: found, transient: false)
            }
            return clipOrFallback(
                "S4_working_general", appearance
            )
        case .working:
            return clipOrFallback(
                "S4_working_general", appearance
            )
        case .done:
            return clipOrFallback(
                "S6_done", appearance, transient: true
            )
        case .waking:
            // 醒来片段仅深色一份：浅色不拿深色片凑
            guard appearance == .dark,
                  let found = entries["S9_asleep_neighbor"]?.dark
            else { return .staticImage(.appearanceMissing) }
            return .clip(fileName: found, transient: true)
        case .thinking, .speaking, .awaiting:
            // 无专属片段：落 S1（兜底表 §479.5）
            return clipOrFallback("S1_idle", appearance)
        case .blocked, .asleep, .listening:
            return .staticImage(.noClipForState)
        }
    }

    private func clipOrFallback(
        _ key: String, _ appearance: LivingAppearance,
        transient: Bool = false
    ) -> LivingClipResolution {
        if let found = pick(
            entries[key], appearance: appearance
        ) {
            return .clip(
                fileName: found, transient: transient
            )
        }
        return .staticImage(.appearanceMissing)
    }

    /// 通话面空闲片段（通话包领地，本期仅目录在
    /// 册、不呈现）：connecting.call 的明暗两档
    public func callIdleClip(
        appearance: LivingAppearance
    ) -> String? {
        guard let entry = entries["connecting"]
        else { return nil }
        switch appearance {
        case .dark: return entry.callDark ?? entry.callLight
        case .light: return entry.callLight
        }
    }
}
