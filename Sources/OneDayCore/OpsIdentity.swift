import Foundation

// MARK: - 身份对账（H1-d 条件子包，台账 158／G-09 余项）
//
// H1-0 探活实证 doctor 本体 10 组全是本体健康、零身份
// 对账项——G-09 的靶心（会话身份工件一致性）不在里面，
// 蓝图预设的改道成立：认领三项（根治版包4 已规划的轻
// 量版口径：binding 值内 id 一致、routing 可达、目录投
// 影完整）改在体检面落成客户端只读核对，挂体检第四组。
//
// 本文件只做判定：输入是 App 层装配的快照（App 所信＋
// 服务端所报），输出逐项结论。数据源全部是现役可读面
// ——会话目录（/api/sessions 全量拉取，与认领同源）、
// /api/status 的网关段、/api/profiles/active。没有读面
// 的东西不造对账：gateway_routing 表本体无客户端读面，
// 本组只证「路由层活着、App 所走的接口通道连着」，表
// 内逐条键值一致性不在客户端可证范围（仍归 G-13 服务
// 端修复线）；/api/host/identity 是 hermes serve 附着
// 用的 rendezvous 所有权证明（属主令牌、非会话面），
// 不当服务端身份端点用。取不到数据的项一律降级「暂
// 无法对账」（incomplete），不许拿别的字段冒充。

/// 对账输入快照：App 所信（本地绑定）＋服务端所报
/// （目录/网关/档案）。任一服务端来源没取到就置 nil，
/// 对应项降级暂无法对账——nil 是「没数据」，不是「零值」。
public struct IdentityReconciliationInput: Sendable, Equatable {
    /// App 所信：本地身份缓存里的主线绑定 id（认领落
    /// 存或冷启动回执）；nil＝本地还没有主线绑定
    public var boundMainSessionID: String?
    /// 主线标题口径（与认领判定同一个值，App 层传入）
    public var expectedMainTitle: String
    /// 服务端所报：会话目录全量快照；nil＝这次没拉到
    public var catalog: CatalogSnapshot?
    /// 本机账本的目录投影条数（缓存口径，只作漂移提
    /// 示、不作判据）；账本没整表加载过时为 nil
    public var localProjectionCount: Int?
    /// 服务端所报：/api/status 的网关段；nil＝没读到
    public var gateway: GatewaySnapshot?
    /// 服务端所报：当前档案名（profiles/active 的
    /// current，缺失时回落 active）。档案在 App 侧没
    /// 有独立的第二真源——只呈现现行值、不判一致
    public var currentProfile: String?

    public struct CatalogSnapshot: Sendable, Equatable {
        public var rows: [Row]
        /// 目录完整性口径（拉全对账的人话结论）：非
        /// nil＝这份目录没拉全，依赖它的项不下结论
        public var incompleteNote: String?

        public init(rows: [Row], incompleteNote: String? = nil) {
            self.rows = rows
            self.incompleteNote = incompleteNote
        }
    }

    public struct Row: Sendable, Equatable {
        public var id: String
        public var title: String?
        public var isArchived: Bool
        public var messageCount: Int?

        public init(
            id: String, title: String?,
            isArchived: Bool, messageCount: Int?
        ) {
            self.id = id
            self.title = title
            self.isArchived = isArchived
            self.messageCount = messageCount
        }
    }

    public struct GatewaySnapshot: Sendable, Equatable {
        public var running: Bool?
        public var state: String?
        /// gateway_platforms["api_server"].state——App
        /// 的消息就经这个接口通道走
        public var apiServerState: String?
        public var version: String?

        public init(
            running: Bool?, state: String?,
            apiServerState: String?, version: String?
        ) {
            self.running = running
            self.state = state
            self.apiServerState = apiServerState
            self.version = version
        }
    }

    public init(
        boundMainSessionID: String?,
        expectedMainTitle: String,
        catalog: CatalogSnapshot?,
        localProjectionCount: Int? = nil,
        gateway: GatewaySnapshot?,
        currentProfile: String?
    ) {
        self.boundMainSessionID = boundMainSessionID
        self.expectedMainTitle = expectedMainTitle
        self.catalog = catalog
        self.localProjectionCount = localProjectionCount
        self.gateway = gateway
        self.currentProfile = currentProfile
    }
}

/// 对账单项结论：人话结论＋（不一致时）哪边为准的提示
public struct IdentityItem: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case mainBinding
        case routing
        case catalog
    }

    public var kind: Kind
    public var title: String
    public var verdict: HealthVerdict
    public var headline: String
    /// 哪边为准/下一步提示；一致时为 nil
    public var authorityNote: String?

    public init(
        kind: Kind, title: String, verdict: HealthVerdict,
        headline: String, authorityNote: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.verdict = verdict
        self.headline = headline
        self.authorityNote = authorityNote
    }
}

/// 一轮身份对账结果：逐项结论＋组合判定。组合口径与
/// 体检其余组同式（四态取最重档），留痕只存 group-
/// Summary 摘要（计数＋一句话），逐项原文不落盘。
public struct IdentityReconciliation: Sendable, Equatable {
    public var items: [IdentityItem]
    /// 服务端当前档案名（只呈现、不判定）
    public var currentProfile: String?

    public init(items: [IdentityItem], currentProfile: String? = nil) {
        self.items = items
        self.currentProfile = currentProfile
    }

    public func item(_ kind: IdentityItem.Kind) -> IdentityItem? {
        items.first { $0.kind == kind }
    }

    public var okCount: Int { items.count { $0.verdict == .ok } }
    public var attentionCount: Int {
        items.count { $0.verdict == .attention }
    }
    public var problemCount: Int {
        items.count { $0.verdict == .problem }
    }

    public var verdict: HealthVerdict {
        items.map(\.verdict).max(by: {
            $0.severityRank < $1.severityRank
        }) ?? .incomplete
    }

    public var headline: String {
        switch verdict {
        case .ok:
            return "身份对账通过：绑定、路由、目录都对得上"
        case .attention:
            return "身份对账有 \(attentionCount) 项要注意"
        case .problem:
            return "身份对账发现 \(problemCount) 项对不上"
        case .incomplete:
            return "身份对账没跑完"
        }
    }

    public var groupSummary: HealthGroupSummary {
        HealthGroupSummary(
            verdict: verdict, headline: headline,
            passCount: okCount, warnCount: attentionCount,
            failCount: problemCount
        )
    }
}

/// 身份对账判定（纯函数）：三项逐项判，互不牵连——
/// 一项没数据只降级它自己，其余项照常出结论。
public enum IdentityReconciler {
    public static func reconcile(
        _ input: IdentityReconciliationInput
    ) -> IdentityReconciliation {
        IdentityReconciliation(
            items: [
                bindingItem(input),
                routingItem(input),
                catalogItem(input),
            ],
            currentProfile: input.currentProfile
        )
    }

    // MARK: 主线绑定（binding 值内 id 一致）

    private static func bindingItem(
        _ input: IdentityReconciliationInput
    ) -> IdentityItem {
        let title = "主线绑定"
        guard let boundID = input.boundMainSessionID,
              !boundID.isEmpty else {
            return IdentityItem(
                kind: .mainBinding, title: title,
                verdict: .incomplete,
                headline: "本地还没有主线绑定，没法核对",
                authorityNote: "先打开主线完成认领，绑定落存后这里会核对它在服务端还在不在。"
            )
        }
        guard let catalog = input.catalog else {
            return IdentityItem(
                kind: .mainBinding, title: title,
                verdict: .incomplete,
                headline: "这次没拉到服务端目录，没法核对主线绑定"
            )
        }
        if let note = catalog.incompleteNote {
            return IdentityItem(
                kind: .mainBinding, title: title,
                verdict: .incomplete,
                headline: "服务端目录没拉全（\(note)），这次不下结论"
            )
        }
        guard let row = catalog.rows.first(where: {
            $0.id == boundID
        }) else {
            return IdentityItem(
                kind: .mainBinding, title: title,
                verdict: .problem,
                headline: "本地绑定的主线，服务端目录里已经没有了",
                authorityNote: "以服务端目录为准——在设置里对主线重新发现一次，就能改认现有的会话。"
            )
        }
        guard row.title == input.expectedMainTitle else {
            return IdentityItem(
                kind: .mainBinding, title: title,
                verdict: .attention,
                headline: "主线绑定还在，但服务端标题对不上了",
                authorityNote: "标题以服务端为准，本地不改它；如果是在别的设备上改过名，这里看到的就是改名后的状态。"
            )
        }
        return IdentityItem(
            kind: .mainBinding, title: title,
            verdict: .ok,
            headline: row.isArchived
                ? "主线绑定对得上（这条会话在服务端是归档状态）"
                : "主线绑定对得上——服务端目录里就是这条会话"
        )
    }

    // MARK: 消息路由（routing 可达）

    private static func routingItem(
        _ input: IdentityReconciliationInput
    ) -> IdentityItem {
        let title = "消息路由"
        guard let gateway = input.gateway else {
            return IdentityItem(
                kind: .routing, title: title,
                verdict: .incomplete,
                headline: "暂无法对账：服务端没报回网关状态"
            )
        }
        // 网关明确没在跑（running=false 或状态词不是
        // running）——消息路由的第一段就断了
        let stopped = gateway.running == false
            || (gateway.state != nil && gateway.state != "running")
        if stopped {
            return IdentityItem(
                kind: .routing, title: title,
                verdict: .problem,
                headline: "消息网关没在运行",
                authorityNote: "网关状态以服务端为准；先到服务器管理里把网关启动起来。"
            )
        }
        guard gateway.running == true || gateway.state == "running"
        else {
            // 字段不足以断言网关活着——不往好处猜
            return IdentityItem(
                kind: .routing, title: title,
                verdict: .incomplete,
                headline: "暂无法对账：服务端没报清网关状态"
            )
        }
        if let apiState = gateway.apiServerState,
           apiState != "connected" {
            return IdentityItem(
                kind: .routing, title: title,
                verdict: .problem,
                headline: "消息网关在运行，但接口通道没连上",
                authorityNote: "通道状态以服务端为准；聊天收发走的就是这条通道，它没连上时先到服务器管理里看网关状态。"
            )
        }
        return IdentityItem(
            kind: .routing, title: title,
            verdict: .ok,
            headline: "消息网关在运行，接口通道已连接"
        )
    }

    // MARK: 会话目录（目录投影完整）

    private static func catalogItem(
        _ input: IdentityReconciliationInput
    ) -> IdentityItem {
        let title = "会话目录"
        guard let catalog = input.catalog else {
            return IdentityItem(
                kind: .catalog, title: title,
                verdict: .incomplete,
                headline: "这次没拉到服务端目录"
            )
        }
        if let note = catalog.incompleteNote {
            return IdentityItem(
                kind: .catalog, title: title,
                verdict: .incomplete,
                headline: "目录没拉全（\(note)），这次不下结论"
            )
        }
        let rows = catalog.rows
        guard !rows.isEmpty else {
            return IdentityItem(
                kind: .catalog, title: title,
                verdict: .attention,
                headline: "服务端目录是空的——还没有任何会话"
            )
        }
        let missingCounts = rows.count { $0.messageCount == nil }
        let archivedCount = rows.count { $0.isArchived }
        let driftNote: String? = input.localProjectionCount
            .flatMap { local in
                local != rows.count
                    ? "本机缓存的目录条数和刚拉到的不一样——以刚拉到的服务端目录为准。"
                    : nil
            }
        if missingCounts > 0 {
            return IdentityItem(
                kind: .catalog, title: title,
                verdict: .attention,
                headline: "目录共 \(rows.count) 条，其中 \(missingCounts) 条没报消息数",
                authorityNote: driftNote
            )
        }
        return IdentityItem(
            kind: .catalog, title: title,
            verdict: .ok,
            headline: "会话目录完整：共 \(rows.count) 条"
                + "（可见 \(rows.count - archivedCount)、归档 \(archivedCount)），每条都带消息数",
            authorityNote: driftNote
        )
    }
}
