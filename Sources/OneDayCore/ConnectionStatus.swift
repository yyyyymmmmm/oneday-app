import Foundation

/// 连接状态一等公民（总表 156，DESIGN §394）：连接阶
/// 段＋第几次尝试＋人话失败原因的单源状态机。此前这三
/// 样散在各处：探活的轮内重探次数是 OverviewBridge-
/// Store 的局部变量、失败原因在 catch 里被吞、呈现层
/// 只有 OverviewStatusLine 的短词三态（在线/待审批/
/// 联系不上，用户点名定版、本模型不碰它）。本模型只
/// 管「现在连到哪一步、试了几次、为什么不行」，由
/// App 层探活链喂事件、自检面等呈现层只读消费；判定
/// 迟滞（连失几才定版离线）仍归 ConnectionLiveness，
/// 本模型只记账不另立阈值。
public enum ConnectionPhase: Equatable, Sendable {
    /// 未连接（无配置/已退出连接态）
    case notConnected
    /// 探活中（尚无任何结论）
    case probing
    /// 已连接（探活或真实业务成功）
    case online
    /// 重探中（已有失败、未定版离线、正在重试）
    case retrying
    /// 定版离线（迟滞阈值已达）
    case offline
}

public struct ConnectionStatus: Equatable, Sendable {
    public private(set) var phase: ConnectionPhase = .notConnected
    /// 当前轮次内已尝试次数（探活口径：首探记 1）
    public private(set) var attempt: Int = 0
    /// 最近一次失败的人话原因（口径与自检面 SelfCheck-
    /// Failure.reasonText 同源，由 App 层映射后注入）
    public private(set) var reason: String?
    public private(set) var updatedAt: Date?

    public init() {}

    /// 一轮探活开始：离线/未连接转探活中；已连接的稳
    /// 态轮询不闪阶段（只清尝试计数备新一轮记账）；探
    /// 活/重探进行中保持原阶段
    public mutating func beginProbe(at date: Date) {
        switch phase {
        case .online:
            attempt = 0
        case .notConnected, .offline:
            phase = .probing
            attempt = 0
        case .probing, .retrying:
            break
        }
        updatedAt = date
    }

    /// 一次探活失败：settledOffline＝迟滞记账已定版离
    /// 线（ConnectionLiveness 的结论，由喂入方给出，
    /// 本模型不自判阈值）
    public mutating func probeFailed(
        attempt: Int, reason: String, settledOffline: Bool,
        at date: Date
    ) {
        self.attempt = max(1, attempt)
        self.reason = reason
        phase = settledOffline ? .offline : .retrying
        updatedAt = date
    }

    /// 探活成功或真实业务成功（同权，§86 口径）：回
    /// 已连接、尝试与原因清零
    public mutating func probeSucceeded(at date: Date) {
        phase = .online
        attempt = 0
        reason = nil
        updatedAt = date
    }

    /// 退出连接态（未连接/断开配置）
    public mutating func markNotConnected(at date: Date) {
        phase = .notConnected
        attempt = 0
        reason = nil
        updatedAt = date
    }

    /// 阶段短词（呈现层标题位）
    public var phaseWord: String {
        switch phase {
        case .notConnected: return "未连接"
        case .probing: return "连接中"
        case .online: return "已连接"
        case .retrying: return "重连中"
        case .offline: return "联系不上"
        }
    }

    /// 阶段细目（呈现层副行）：第几次尝试＋人话原因；
    /// 无细目可报时 nil（已连接/未连接不占位）
    public var detailText: String? {
        switch phase {
        case .notConnected, .online:
            return nil
        case .probing:
            return attempt > 0 ? "第 \(attempt) 次尝试" : nil
        case .retrying:
            var parts = ["第 \(attempt) 次尝试"]
            if let reason { parts.append(reason) }
            return parts.joined(separator: "，")
        case .offline:
            var parts: [String] = []
            if let reason { parts.append(reason) }
            if attempt > 0 { parts.append("共 \(attempt) 次尝试") }
            return parts.isEmpty ? nil : parts.joined(separator: "，")
        }
    }
}
