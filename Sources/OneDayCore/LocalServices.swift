import Foundation

/// 本机服务（0.29.0，连接器目录补组）：这台服务器自
/// 家的四条线——Hermes 本体、记忆与技能（write-gate
/// 审批桥）、目标与点子（oneday-bridge）、总览数据
/// （overview-bridge）。它们的功能页在 App 内早已在
/// 用，缺的只是目录里的名分与状态。本文件只管静态
/// 名册与探活状态的纯判定（状态文案单一映射、结局
/// →状态映射、搜索纯函数）；探活动作（各桥既有客户
/// 端的只读 GET）在 App 层，口径与各功能页同源，不
/// 另起第二套地址/钥匙配置。
///
/// 状态真实纪律（与 ConnectorCatalog 同）：状态只
/// 来自进页当场检查——正常＝本次检查成功；异常＝
/// 本次检查失败（错误原文随状态带出、上详情显）；
/// 未配置＝登录信息不在这台手机上（0.33.1 起各桥
/// 统一走 Hermes 登录一把钥、服务器内部分权对
/// App 不可见；无登录信息时客户端根本不发请求，
/// noKey 结局映射到此档，不许报成异常）；读取中
/// ＝首帧未回。不设「上次结果」缓存位，视图每次
/// 进页/下拉重探。

/// 本机服务标识（名册序即目录呈现序）
public enum LocalServiceID: String, CaseIterable, Identifiable, Sendable {
    case hermes
    case writeGate
    case oneDayBridge
    case overviewBridge

    public var id: String { rawValue }
}

/// 本机服务静态条目：名称/说明/图标/检查证据全
/// 在 Core 单一真源，视图只渲染（与
/// ConnectorCatalog Entry 同式）。图标口径
/// （0.36.3，用户 18:05 加严 §4 执行口径）：有名
/// 有姓的服务一律真实图标——本机服务逐个定制应
/// 用图标级图面进 Assets（iconAssetName，来源与
/// 画法登记在整改台账 D 节），旧「裸 SF 符号瓷
/// 砖」自本版退役；裸符号只许留无名未知 MCP 兜
/// 底。evidenceLine 是检查的证据口径——检查的
/// 是什么、为何这样查，详情页以用户语言如实列
/// 出（接口细节不进主文案，§8）。
public struct LocalServiceDescriptor: Identifiable, Equatable, Sendable {
    public let serviceID: LocalServiceID
    public let name: String
    /// 一句说明（列表行副题与详情共用）
    public let blurb: String
    /// 定制图标面资产名（Assets.xcassets 内 imageset）
    public let iconAssetName: String
    /// 检查证据来源（用户语言）
    public let evidenceLine: String

    public var id: String { serviceID.rawValue }

    public init(
        serviceID: LocalServiceID, name: String, blurb: String,
        iconAssetName: String, evidenceLine: String
    ) {
        self.serviceID = serviceID
        self.name = name
        self.blurb = blurb
        self.iconAssetName = iconAssetName
        self.evidenceLine = evidenceLine
    }
}

public enum LocalServiceDirectory {
    /// 名册全集（呈现序＝声明序：本体→审批桥→目
    /// 标点子→总览）。电脑（Simular Box）是 MCP 在
    /// 册连接、留在「已连接」组原位，本组不重复列。
    public static let roster: [LocalServiceDescriptor] = [
        LocalServiceDescriptor(
            serviceID: .hermes,
            name: "Hermes 服务",
            blurb: "智能体本体 · 对话、工具与会话都跑在它上面",
            iconAssetName: "LocalHermes",
            evidenceLine: "检查的是 Hermes 本体回的健康状态（打开本页时当场问的，不需要登录）"
        ),
        LocalServiceDescriptor(
            serviceID: .writeGate,
            name: "记忆与技能",
            blurb: "记忆和技能的写入，先经你批准再生效",
            iconAssetName: "LocalWriteGate",
            evidenceLine: "检查的是写入审批的工作状态（打开本页时当场问的）"
        ),
        LocalServiceDescriptor(
            serviceID: .oneDayBridge,
            name: "目标与点子",
            blurb: "目标与点子的云端仓 · 底栏目标/点子两格的数据源",
            iconAssetName: "LocalOneDayBridge",
            evidenceLine: "检查的是目标列表能不能读到（这项服务没有专门的健康检查，拿最轻的一次读取代替）"
        ),
        LocalServiceDescriptor(
            serviceID: .overviewBridge,
            name: "总览数据",
            blurb: "总览 · 总览页与通知角标的数据来源",
            iconAssetName: "LocalOverviewBridge",
            evidenceLine: "检查的是总览数据能不能读到（这项服务没有专门的健康检查，拿最轻的一次读取代替）"
        ),
    ]

    public static func descriptor(
        _ id: LocalServiceID
    ) -> LocalServiceDescriptor {
        // 名册恒含四条全集，查不到即编程错误——以首
        // 条兜底而非崩溃（呈现层宁可显错条不许闪退）
        roster.first { $0.serviceID == id } ?? roster[0]
    }
}

/// 探活结局（App 层把各客户端的错误翻译成本枚举后
/// 交映射；翻译口径在 App 层各探活函数内，映射只此
/// 一处）：成功可带一条真实读数（metric，如技能数/
/// 目标数——取不到为 nil，不编造）。
public enum LocalServiceProbeOutcome: Equatable, Sendable {
    case success(metric: String?)
    /// 检查失败（人话错误原文，详情显）
    case failure(String)
    /// 登录信息未设置（客户端未发请求）
    case keyNotConfigured
}

/// 探活状态（视图呈现源）：四档与简报一一对应。
public enum LocalServiceProbeState: Equatable, Sendable {
    case loading
    case up(metric: String?)
    case down(message: String)
    case notConfigured

    /// 状态文案单一映射（列表行与详情共用一处）
    public var statusLabel: String {
        switch self {
        case .loading: return "读取中"
        case .up: return "正常"
        case .down: return "异常"
        case .notConfigured: return "未配置"
        }
    }

    public var metric: String? {
        if case .up(let metric) = self { return metric }
        return nil
    }

    /// 列表副行全形：状态＋读数（有读数才拼，不留空尾）
    public var subline: String {
        if let metric, !metric.isEmpty {
            return "\(statusLabel) · \(metric)"
        }
        return statusLabel
    }
}

public enum LocalServiceProbeMapping {
    /// 结局→状态：映射只此一处，三路（成功/失败/
    /// 钥匙未配）在 LocalServicesTests 钉死
    public static func state(
        from outcome: LocalServiceProbeOutcome
    ) -> LocalServiceProbeState {
        switch outcome {
        case .success(let metric): return .up(metric: metric)
        case .failure(let message): return .down(message: message)
        case .keyNotConfigured: return .notConfigured
        }
    }

    // MARK: - 搜索（真过滤：名称＋说明＋状态词，纯函数）

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func matches(
        _ descriptor: LocalServiceDescriptor,
        state: LocalServiceProbeState, query: String
    ) -> Bool {
        let q = normalized(query)
        if q.isEmpty { return true }
        let fields = [
            descriptor.name, descriptor.blurb,
            descriptor.serviceID.rawValue, state.statusLabel,
        ]
        return fields.contains { normalized($0).contains(q) }
    }

    /// 名册按搜索词过滤（保持名册序）
    public static func filtered(
        states: [LocalServiceID: LocalServiceProbeState], query: String
    ) -> [LocalServiceDescriptor] {
        LocalServiceDirectory.roster.filter { descriptor in
            matches(
                descriptor,
                state: states[descriptor.serviceID] ?? .loading,
                query: query
            )
        }
    }
}
