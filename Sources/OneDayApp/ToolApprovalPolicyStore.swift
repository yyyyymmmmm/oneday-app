import Foundation
import OneDayDesign
import SwiftUI

/// 单工具/连接器读写审批策略档位（对标 Claude Connectors / MCP 2026-07-28 规范）：
/// 让用户为每个 MCP 连接器精细指定调用授权边界。
enum ToolApprovalTier: String, CaseIterable, Identifiable, Codable {
    case readOnlyAuto = "read_only_auto"
    case confirmWrites = "confirm_writes"
    case alwaysAsk = "always_ask"
    case disabled = "disabled"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readOnlyAuto: return "只读自动 · 写入确认"
        case .confirmWrites: return "仅高危写入确认"
        case .alwaysAsk: return "每次调用均确认"
        case .disabled: return "禁止 AI 调用"
        }
    }

    var shortBadge: String {
        switch self {
        case .readOnlyAuto: return "只读自动"
        case .confirmWrites: return "写入确认"
        case .alwaysAsk: return "每次确认"
        case .disabled: return "已禁用"
        }
    }

    var subtitle: String {
        switch self {
        case .readOnlyAuto:
            return "查询/检索类工具自动放行，修改/删除/发送类写入操作弹窗确认。"
        case .confirmWrites:
            return "常规读写自动执行，仅破坏性或不可逆操作需人工确认。"
        case .alwaysAsk:
            return "该连接器下所有工具调用前均需你点击允许。"
        case .disabled:
            return "暂时屏蔽此连接器下的全部工具，保留配置不删除。"
        }
    }

    var tint: Color {
        switch self {
        case .readOnlyAuto: return Palette.tintGreenInk
        case .confirmWrites: return Palette.tintSkyInk
        case .alwaysAsk: return Palette.tintOrangeInk
        case .disabled: return Palette.danger
        }
    }
}

/// 单连接器审批策略持久化仓库（本机偏好单源，支持后续与服务端配置双向同步）
@MainActor
@Observable
final class ToolApprovalPolicyStore {
    static let shared = ToolApprovalPolicyStore()

    private let storageKey = "oneday.mcp.tool_approval_policies.v1"
    private(set) var policies: [String: ToolApprovalTier] = [:]

    private init() {
        load()
    }

    func tier(for connectorKey: String) -> ToolApprovalTier {
        policies[connectorKey] ?? .readOnlyAuto
    }

    func setTier(_ tier: ToolApprovalTier, for connectorKey: String) {
        policies[connectorKey] = tier
        save()
    }

    private func load() {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] else {
            return
        }
        var decoded: [String: ToolApprovalTier] = [:]
        for (k, v) in raw {
            if let tier = ToolApprovalTier(rawValue: v) {
                decoded[k] = tier
            }
        }
        policies = decoded
    }

    private func save() {
        let raw = policies.mapValues(\.rawValue)
        UserDefaults.standard.set(raw, forKey: storageKey)
    }
}
