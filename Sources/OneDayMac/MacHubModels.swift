import Foundation
import OneDayCore

/// 枢纽面注册表（棒 4，对位 #11 入口）：面序与拟案
/// 1.4 枢纽行一致；21/22 号（选项卡/表情反应）按
/// 2026-11-26 17:39 裁定归「聊天补全小棒」，不在本表。
enum MacHubFace: String, CaseIterable, Identifiable {
    case ledger, audit, computer, identity, mail
    case profiles, memory, skills, toolsets, delegation
    case cron, mcp, connectors, channels, devices
    case monitors, webhooks, presets, env, kanban
    case gateway, models, pairing, usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ledger: return "工作台账"
        case .audit: return "审计"
        case .computer: return "电脑"
        case .identity: return "身份"
        case .mail: return "邮件"
        case .profiles: return "档案"
        case .memory: return "记忆"
        case .skills: return "技能"
        case .toolsets: return "工具集"
        case .delegation: return "委派"
        case .cron: return "定时任务"
        case .mcp: return "MCP"
        case .connectors: return "连接器"
        case .channels: return "频道"
        case .devices: return "设备与主会话"
        case .monitors: return "监控"
        case .webhooks: return "Webhooks"
        case .presets: return "预设"
        case .env: return "环境变量"
        case .kanban: return "看板"
        case .gateway: return "网关状态"
        case .models: return "模型与服务商"
        case .pairing: return "配对管理"
        case .usage: return "用量"
        }
    }

    var systemImage: String {
        switch self {
        case .ledger: return "list.clipboard"
        case .audit: return "checkmark.shield"
        case .computer: return "desktopcomputer"
        case .identity: return "person.crop.circle"
        case .mail: return "envelope"
        case .profiles: return "person.text.rectangle"
        case .memory: return "brain"
        case .skills: return "wand.and.stars"
        case .toolsets: return "wrench.and.screwdriver"
        case .delegation: return "arrow.triangle.branch"
        case .cron: return "clock.arrow.circlepath"
        case .mcp: return "server.rack"
        case .connectors: return "cable.connector"
        case .channels: return "bubble.left.and.bubble.right"
        case .devices: return "iphone.and.arrow.forward"
        case .monitors: return "waveform.path.ecg"
        case .webhooks: return "link.badge.plus"
        case .presets: return "slider.horizontal.3"
        case .env: return "key"
        case .kanban: return "rectangle.3.group"
        case .gateway: return "network"
        case .models: return "cpu"
        case .pairing: return "person.2.badge.key"
        case .usage: return "chart.bar"
        }
    }

    /// 对位表件号（docs/mac-parity.md 口径）
    var parityNumber: Int {
        switch self {
        case .ledger: return 39
        case .audit: return 40
        case .computer: return 41
        case .identity: return 42
        case .mail: return 43
        case .profiles: return 44
        case .memory: return 45
        case .skills: return 46
        case .toolsets: return 47
        case .delegation: return 48
        case .cron: return 49
        case .mcp: return 50
        case .connectors: return 51
        case .channels: return 52
        case .devices: return 53
        case .monitors: return 54
        case .webhooks: return 55
        case .presets: return 56
        case .env: return 57
        case .kanban: return 58
        case .gateway: return 59
        case .models: return 63
        case .pairing: return 62
        case .usage: return 64
        }
    }
}

/// JSONValue 宽容提取（管理面呈现共用）：服务端字段
/// 随版本漂移，取不到就给空/缺省，不整面解码失败。
/// 与 Core 的 KanbanFields 同思路，落在 App 目标内
/// 供各枢纽面共用（Core 内的同名访问器是文件私有的）。
extension JSONValue {
    var hubDict: [String: JSONValue] {
        if case .object(let dict) = self { return dict }
        return [:]
    }

    var hubList: [JSONValue] {
        if case .array(let values) = self { return values }
        return []
    }

    func hubStr(_ key: String) -> String? {
        hubDict[key]?.stringValue
    }

    func hubBool(_ key: String) -> Bool? {
        hubDict[key]?.boolValue
    }

    func hubNum(_ key: String) -> Double? {
        if case .number(let value) = hubDict[key] ?? .null {
            return value
        }
        return nil
    }

    /// 信封宽容：依次在给定键下找数组，都没有时若
    /// 本体是数组就用本体
    func hubFirstList(_ keys: [String]) -> [JSONValue] {
        for key in keys {
            if case .array(let values) = hubDict[key] ?? .null {
                return values
            }
        }
        return hubList
    }

    /// 信封宽容取字符串：依次试多个键名
    func hubFirstStr(_ keys: [String]) -> String? {
        for key in keys {
            if let value = hubDict[key]?.stringValue {
                return value
            }
        }
        return nil
    }
}

/// 环境变量行（GET /api/env 顶层字典映射）
struct MacEnvRow: Identifiable, Equatable {
    let key: String
    let isSet: Bool
    let redacted: String?
    let note: String?

    var id: String { key }
}

/// 键值展示行（状态类面共用）
struct MacKVRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}
