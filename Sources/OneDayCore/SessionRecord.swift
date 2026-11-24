import Foundation

/// 会话账本记录（第 67 条收口包一，2026-11-15）：一行
/// 一会话的合并名单值型——呈现层唯一输入。合并键＝
/// ChatThread.serverSessionID；未收养服务端会话与纯
/// 本地线程都是正式记录，形态由列区分。合并与投影
/// 全是纯函数（本文件），账本店（App 层 Session-
/// Ledger）只管状态与同步——防账本长成新的聚合巨
/// 石（设计纪律 R5）。分类只是一列：origin 在合并
/// 时统一算一次（输入集恒为账本全量名单＋全量关联
/// 集，结束各面四套输入集的漂移）；birthRule 记命
/// 中规则号，「指着一条能答出从哪来」（方案 A §0
/// 验收问句）。存储零迁移：本型只是内存合并结果，
/// 底层仍是 SwiftData ChatThread＋服务端名单＋
/// UserDefaults 侧账原键。

/// 本地线程的账本快照（App 层自 ChatThread 逐字段
/// 摘出喂合并；账本不自持 ModelContext，各面 @Query
/// 的 [ChatThread] 在刷新/呈现时经本型注入——避开
/// 账本自持上下文的生命周期与多容器问题）
public struct LedgerLocalThread: Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var titleIsManual: Bool
    public var serverSessionID: String?
    public var isPendingDeletion: Bool
    public var isPinned: Bool
    public var updatedAt: Date
    public var createdAt: Date
    public var linkFailureCount: Int
    public var linkLastError: String?

    public init(
        id: UUID, title: String, titleIsManual: Bool,
        serverSessionID: String?, isPendingDeletion: Bool,
        isPinned: Bool, updatedAt: Date, createdAt: Date,
        linkFailureCount: Int, linkLastError: String?
    ) {
        self.id = id
        self.title = title
        self.titleIsManual = titleIsManual
        self.serverSessionID = serverSessionID
        self.isPendingDeletion = isPendingDeletion
        self.isPinned = isPinned
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.linkFailureCount = linkFailureCount
        self.linkLastError = linkLastError
    }
}

/// 归档列的真相来源标注（设计 §2.3）：分脑规则显式
/// 写在列上，不再靠 §233 回写对齐两本账——过服务端
/// 回写闸的绑定线程以服务端归档段为准（.server），
/// 纯本地/主线/合并桶以本地归档键为准（.local）
public enum LedgerArchiveSource: Sendable, Equatable {
    case server
    case local
}

/// 链接相位列（SideChatLink 三相的记录投影）：发送
/// 面读列不重算。无本地线程的服务端记录恒 .unlinked
/// （本地未收养即未链接）
public enum LedgerLinkPhase: Sendable, Equatable {
    case unlinked
    case linked
    case failed(count: Int)
}

/// 名单完整性列（B-1 防护的接口级形态）：存活集只
/// 许连完整性一并交出——complete 才可用于对账删除
/// 判定，incomplete 只可留痕/呈现，消费方拿不到
/// 「裸 ids」去做删除判定
public enum LedgerCompleteness: Sendable, Equatable {
    case complete
    case incomplete(reason: String)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

/// 记录所在的服务端名单段（合并输入口径）：管理页
/// 两段投影与存活集按本列取行
public enum LedgerSegment: Sendable, Equatable {
    /// archived=exclude 拉回的可见段
    case visible
    /// archived=only 拉回的已归档段
    case archived
    /// 服务端名单里没有（纯本地线程，或名单未含其
    /// 关联会话）
    case none
}

/// 账本记录（一行一会话）。不声明 Equatable：
/// ServerSession 本体无 Equatable，行集比较一律
/// 走 ledgerID（测试同口径）
public struct SessionRecord: Sendable, Identifiable {
    /// 本地线程在：local:<uuid>；未收养：server:<id>
    /// （与现归档键命名空间同形，迁移零翻译）
    public var ledgerID: String
    public var id: String { ledgerID }
    public var localThreadID: UUID?
    public var serverSessionID: String?
    /// 层归属（分类列，合并时统一算）
    public var origin: SessionLayer
    /// 出生证明明细：命中规则号（R0/R2/R3/R3b…）
    public var birthRule: String
    /// 标题（标题单管线结果：第 67 条包二起两段入
    /// 参适配同一 SessionTitlePipeline 核心——本地
    /// 线程行喂手改名/服务端标题/本地快照，服务端
    /// 行喂服务端标题/派生/人话名）
    public var title: String
    public var archived: Bool
    public var archiveSource: LedgerArchiveSource
    public var isPendingDeletion: Bool
    /// 来源原始标识（服务端会话的 source；纯本地
    /// 线程为 nil）
    public var source: String?
    /// 活动时间（本地行＝线程 updatedAt；服务端行＝
    /// 结束时间 ?? 开始时间，两者皆无为 nil）
    public var activityAt: Date?
    public var linkPhase: LedgerLinkPhase
    /// 服务端行本体（名单里有其会话时在场；管理页
    /// 等按 ServerSession 呈现的投影直接取它）
    public var session: ServerSession?
    /// 所在名单段（纯本地线程为 .none）
    public var segment: LedgerSegment
    /// 段内序号（投影保服务端原序用）
    public var segmentIndex: Int
    /// 本地线程输入序（抽屉本地行保 @Query 序用；
    /// 无本地线程为 nil）
    public var localIndex: Int?

    public init(
        ledgerID: String, localThreadID: UUID?,
        serverSessionID: String?, origin: SessionLayer,
        birthRule: String, title: String, archived: Bool,
        archiveSource: LedgerArchiveSource,
        isPendingDeletion: Bool, source: String?,
        activityAt: Date?, linkPhase: LedgerLinkPhase,
        session: ServerSession?, segment: LedgerSegment,
        segmentIndex: Int, localIndex: Int?
    ) {
        self.ledgerID = ledgerID
        self.localThreadID = localThreadID
        self.serverSessionID = serverSessionID
        self.origin = origin
        self.birthRule = birthRule
        self.title = title
        self.archived = archived
        self.archiveSource = archiveSource
        self.isPendingDeletion = isPendingDeletion
        self.source = source
        self.activityAt = activityAt
        self.linkPhase = linkPhase
        self.session = session
        self.segment = segment
        self.segmentIndex = segmentIndex
        self.localIndex = localIndex
    }
}

/// 合并纯函数：服务端两段名单＋本地线程快照＋侧账
/// 输入 → 合并记录集。输入口径与现行各面同源（关
/// 联集走 ThreadLinkage 同式派生：非主线关联才算出
/// 生/收养证明）
public enum SessionLedgerMerge {
    /// 合并入参（侧账快照，App 层自 SideChatStore 与
    /// 删除队列、标题解析器缓存摘出）
    public struct Inputs: Sendable {
        public var mainThreadID: UUID?
        public var mainServerSessionID: String?
        public var archivedKeys: Set<String>
        public var pendingDeletionIDs: Set<String>
        public var firstUserMessages: [String: String]

        public init(
            mainThreadID: UUID?,
            mainServerSessionID: String?,
            archivedKeys: Set<String>,
            pendingDeletionIDs: Set<String>,
            firstUserMessages: [String: String]
        ) {
            self.mainThreadID = mainThreadID
            self.mainServerSessionID = mainServerSessionID
            self.archivedKeys = archivedKeys
            self.pendingDeletionIDs = pendingDeletionIDs
            self.firstUserMessages = firstUserMessages
        }
    }

    /// 出生证明规则号：与 SessionClassifier.classify
    /// 同链同序（谓词全同源），只多回规则号——两处
    /// 一致性由 SessionLedgerTests 的规则↔层对照矩
    /// 阵钉住，分类口径变更须两处同改
    public static func birthRule(
        id: String, source: String?, sessionKey: String?,
        mainServerSessionID: String?,
        linkedThreadSessionIDs: Set<String>
    ) -> String {
        if SideChatClassifier.isMain(
            serverSessionID: id,
            mainServerSessionID: mainServerSessionID
        ) {
            return "R0"
        }
        if SideChatLink.isMergeBucket(id) { return "R1" }
        let effective = SessionSources.effectiveSource(
            source: source, sessionKey: sessionKey
        )
        if linkedThreadSessionIDs.contains(id),
           !SessionSources.isNonUserChannel(effective) {
            return "R2"
        }
        if id.hasPrefix(SessionClassifier.appSideSessionPrefix) {
            return "R3"
        }
        if id.hasPrefix(SessionClassifier.aiCastSessionPrefix) {
            return "R3b"
        }
        if id.hasPrefix(SideChatLink.ownSessionPrefix) {
            return "R4"
        }
        if id.hasPrefix(SessionClassifier.runCastPrefix)
            || id.hasPrefix(SessionClassifier.probeCastPrefix) {
            return "R4b"
        }
        if let effective,
           SessionSources.structuralSystem.contains(effective) {
            return "R5"
        }
        if let effective {
            let canonical = SessionSources.canonicalPlatform(
                effective
            )
            if SessionSources.platforms.contains(canonical) {
                return "R6"
            }
        }
        if let effective,
           SessionSources.hermesSurfaces.contains(effective) {
            return "R7"
        }
        return "R8/R9"
    }

    public static func records(
        visible: [ServerSession],
        archived: [ServerSession],
        localThreads: [LedgerLocalThread],
        inputs: Inputs
    ) -> [SessionRecord] {
        // 关联集（ThreadLinkage 同式：非主线关联才
        // 算出生/收养证明）
        var linked = Set<String>()
        for thread in localThreads {
            guard let sessionID = thread.serverSessionID,
                  !sessionID.isEmpty else { continue }
            if SideChatClassifier.isMain(
                localThreadID: thread.id,
                linkedServerSessionID: sessionID,
                mainThreadID: inputs.mainThreadID,
                mainServerSessionID: inputs.mainServerSessionID
            ) {
                continue
            }
            linked.insert(sessionID)
        }
        // 服务端索引：id → (行本体, 段, 段内序)。同
        // id 两段都在时可见段优先（服务端正常口径下
        // 一条会话只在一段里）
        var serverByID: [String: (session: ServerSession,
                                   segment: LedgerSegment,
                                   index: Int)] = [:]
        for (index, session) in visible.enumerated() {
            serverByID[session.id] = (session, .visible, index)
        }
        for (index, session) in archived.enumerated()
        where serverByID[session.id] == nil {
            serverByID[session.id] = (session, .archived, index)
        }
        var threadBySessionID: [String: LedgerLocalThread] = [:]
        for thread in localThreads {
            if let sessionID = thread.serverSessionID,
               !sessionID.isEmpty {
                threadBySessionID[sessionID] = thread
            }
        }

        var result: [SessionRecord] = []
        var emittedSessions = Set<String>()
        // 本地线程行（保输入序）：有关联会话者与服务
        // 端行合并为一条
        for (localIndex, thread) in localThreads.enumerated() {
            let server = thread.serverSessionID.flatMap {
                serverByID[$0]
            }
            if let sessionID = thread.serverSessionID {
                emittedSessions.insert(sessionID)
            }
            result.append(threadRecord(
                thread: thread, localIndex: localIndex,
                server: server, inputs: inputs, linked: linked
            ))
        }
        // 未收养服务端行：可见段原序在前、已归档段
        // 原序在后
        for (segment, list) in [(LedgerSegment.visible, visible),
                                (LedgerSegment.archived, archived)] {
            for (index, session) in list.enumerated() {
                guard !emittedSessions.contains(session.id),
                      serverByID[session.id]?.segment == segment
                else { continue }
                emittedSessions.insert(session.id)
                result.append(serverRecord(
                    session: session, segment: segment,
                    index: index, inputs: inputs, linked: linked
                ))
            }
        }
        return result
    }

    private static func threadRecord(
        thread: LedgerLocalThread, localIndex: Int,
        server: (session: ServerSession, segment: LedgerSegment,
                 index: Int)?,
        inputs: Inputs, linked: Set<String>
    ) -> SessionRecord {
        let session = server?.session
        let isMainThread = SideChatClassifier.isMain(
            localThreadID: thread.id,
            linkedServerSessionID: thread.serverSessionID,
            mainThreadID: inputs.mainThreadID,
            mainServerSessionID: inputs.mainServerSessionID
        )
        let origin: SessionLayer
        let rule: String
        if let session {
            origin = SessionClassifier.classify(
                session: session,
                mainServerSessionID: inputs.mainServerSessionID,
                linkedThreadSessionIDs: linked
            )
            rule = birthRule(
                id: session.id, source: session.source,
                sessionKey: session.sessionKey,
                mainServerSessionID: inputs.mainServerSessionID,
                linkedThreadSessionIDs: linked
            )
        } else if isMainThread {
            // 名单未含其关联会话的主线线程：钦定即出
            // 生证明（§4.4 主线特殊户）
            origin = .main
            rule = "R0"
        } else {
            // 纯本地/链接失败线程：本地出生即证明，
            // origin 恒 mine（§4.4），linkPhase 承载
            // 失败留痕、不因收编丢账
            origin = .mine
            rule = "R2"
        }
        // 标题：本地线程行入参适配（手改名＞服务端
        // 标题＞本地快照）喂标题单管线，优先级实现
        // 在 SessionTitlePipeline 一处（包二合一）
        let title = DrawerThreadTitle.resolve(
            localTitle: thread.title,
            titleIsManual: thread.titleIsManual,
            serverTitle: session?.cleanedServerTitle
        )
        // 归档列：过服务端回写闸的绑定以服务端段为
        // 准；其余（纯本地/主线/合并桶/名单未含）以
        // 本地归档键为准，来源标注如实分列
        let archived: Bool
        let archiveSource: LedgerArchiveSource
        if let session, let segment = server?.segment,
           segment != .none,
           SideChatLink.mayWriteThroughToServer(
               sessionID: session.id,
               mainSessionID: inputs.mainServerSessionID
           ) {
            archived = segment == .archived
            archiveSource = .server
        } else {
            archived = SideChatArchive.isArchived(
                localThreadID: thread.id,
                archivedKeys: inputs.archivedKeys
            )
            archiveSource = .local
        }
        let pending = thread.isPendingDeletion
            || (thread.serverSessionID.map {
                inputs.pendingDeletionIDs.contains($0)
            } ?? false)
        let linkPhase: LedgerLinkPhase
        if thread.serverSessionID != nil {
            linkPhase = .linked
        } else if thread.linkFailureCount > 0 {
            linkPhase = .failed(count: thread.linkFailureCount)
        } else {
            linkPhase = .unlinked
        }
        return SessionRecord(
            ledgerID: "local:\(thread.id.uuidString)",
            localThreadID: thread.id,
            serverSessionID: thread.serverSessionID,
            origin: origin, birthRule: rule, title: title,
            archived: archived, archiveSource: archiveSource,
            isPendingDeletion: pending,
            source: session?.source,
            activityAt: thread.updatedAt,
            linkPhase: linkPhase,
            session: session,
            segment: server?.segment ?? .none,
            segmentIndex: server?.index ?? 0,
            localIndex: localIndex
        )
    }

    private static func serverRecord(
        session: ServerSession, segment: LedgerSegment,
        index: Int, inputs: Inputs, linked: Set<String>
    ) -> SessionRecord {
        let origin = SessionClassifier.classify(
            session: session,
            mainServerSessionID: inputs.mainServerSessionID,
            linkedThreadSessionIDs: linked
        )
        return SessionRecord(
            ledgerID: "server:\(session.id)",
            localThreadID: nil,
            serverSessionID: session.id,
            origin: origin,
            birthRule: birthRule(
                id: session.id, source: session.source,
                sessionKey: session.sessionKey,
                mainServerSessionID: inputs.mainServerSessionID,
                linkedThreadSessionIDs: linked
            ),
            title: session.resolvedTitle(
                firstUserMessage: inputs
                    .firstUserMessages[session.id]
            ),
            archived: segment == .archived,
            archiveSource: .server,
            isPendingDeletion: inputs.pendingDeletionIDs
                .contains(session.id),
            source: session.source,
            activityAt: session.endedDate ?? session.startedDate,
            linkPhase: .unlinked,
            session: session, segment: segment,
            segmentIndex: index, localIndex: nil
        )
    }
}

/// 投影纯函数（账本内唯一实现）：各面行集只许从记
/// 录投影取，不许再自拉自算。过滤口径逐条对现行各
/// 面实现（见各函数注），等值性由 SessionLedger-
/// Tests 对旧实现同夹具对照钉住
public enum LedgerProjection {

    /// 抽屉本地行：现行 drawerItems＋sideThreads 两
    /// 段过滤的投影形——剔待删墓碑与已归档（记录归
    /// 档列），再过 DrawerSideChatFilter（主线/来源
    /// 两判，归档判已在记录列）。保本地输入序
    public static func drawerLocalRows(
        _ records: [SessionRecord]
    ) -> [SessionRecord] {
        records
            .filter { $0.localThreadID != nil }
            .sorted {
                ($0.localIndex ?? 0) < ($1.localIndex ?? 0)
            }
            .filter { record in
                !record.isPendingDeletion && !record.archived
            }
            .filter { record in
                DrawerSideChatFilter.threadListed(
                    isMainThread: record.origin == .main,
                    isLocallyArchived: false,
                    linkedSource: record.source
                )
            }
    }

    /// 抽屉未收养行：现行 DrawerUnadoptedSideChats
    /// 的投影形——无本地线程、分类 .mine、剔待删；
    /// 活动时间倒序（无日期垫底、同刻保记录原序）
    public static func drawerUnadoptedRows(
        _ records: [SessionRecord]
    ) -> [SessionRecord] {
        let picked = records.filter {
            $0.localThreadID == nil
                && $0.origin == .mine
                && !$0.isPendingDeletion
        }
        return picked
            .enumerated()
            .sorted { lhs, rhs in
                let lDate = lhs.element.activityAt
                let rDate = rhs.element.activityAt
                switch (lDate, rDate) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.offset < rhs.offset
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// 抽屉旁聊区合并行集：本地行＋未收养行同区平
    /// 铺、活动时间倒序（现行 sideRows 合并口径：
    /// 同刻保原序、本地行在前）
    public static func drawerSideRows(
        _ records: [SessionRecord]
    ) -> [SessionRecord] {
        let locals = drawerLocalRows(records)
        let unadopted = drawerUnadoptedRows(records)
        var merged: [(record: SessionRecord, date: Date,
                       order: Int)] = []
        for (index, record) in locals.enumerated() {
            merged.append((
                record, record.activityAt ?? .distantPast,
                index
            ))
        }
        for (index, record) in unadopted.enumerated() {
            merged.append((
                record, record.activityAt ?? .distantPast,
                locals.count + index
            ))
        }
        return merged
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.order < rhs.order
            }
            .map(\.record)
    }

    /// 抽屉标题索引（F2，手感快速项 2026-11-23）：
    /// 本地线程 id→记录标题，一趟建成——取代消费
    /// 方逐行 first(where:) 线性扫描（名单派生
    /// O(N²) 本体，审计实测 500 条一趟约 9.9ms、
    /// 扫描占约 8.9ms）。同 id 多条取首个（与
    /// first(where:) 逐字同义）；无本地线程的记
    /// 录不入字典，消费方查无回落本地标题（旧口
    /// 径不变）
    public static func titleByLocalThreadID(
        _ records: [SessionRecord]
    ) -> [UUID: String] {
        var titles: [UUID: String] = [:]
        titles.reserveCapacity(records.count)
        for record in records {
            guard let threadID = record.localThreadID
            else { continue }
            if titles[threadID] == nil {
                titles[threadID] = record.title
            }
        }
        return titles
    }

    /// 管理页可见段：可见段记录的服务端行本体（剔
    /// 待删，保段内原序）——现行 AllConversations-
    /// Store.sessions 的投影形
    public static func managementVisible(
        _ records: [SessionRecord]
    ) -> [ServerSession] {
        records
            .filter {
                $0.segment == .visible
                    && !$0.isPendingDeletion
                    && $0.session != nil
            }
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .compactMap(\.session)
    }

    /// 管理页已归档段：现行 archivedSessions 的投
    /// 影形（剔待删，保段内原序）
    public static func managementArchived(
        _ records: [SessionRecord]
    ) -> [ServerSession] {
        records
            .filter {
                $0.segment == .archived
                    && !$0.isPendingDeletion
                    && $0.session != nil
            }
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .compactMap(\.session)
    }

    /// 频道名单投影：某频道的服务端行（可见段、剔
    /// 待删、保段内原序）。Hermes 频道含合并桶行
    /// （SessionPartition.hermesChannelSessions 同
    /// 口径：普通频道行在前、合并桶行在后）
    public static func channelList(
        _ records: [SessionRecord], channelID: String
    ) -> [ServerSession] {
        let visible = records.filter {
            $0.segment == .visible
                && !$0.isPendingDeletion
                && $0.session != nil
        }
        if channelID == ChannelRegistry.hermesChannelID {
            // SessionPartition 同形：普通频道行（保
            // 段序）在前、合并桶行（保段序）在后
            let rows = visible
                .filter { $0.origin == .channel(channelID) }
                .sorted { $0.segmentIndex < $1.segmentIndex }
            let buckets = visible
                .filter { $0.origin == .mergeBucket }
                .sorted { $0.segmentIndex < $1.segmentIndex }
            return (rows + buckets).compactMap(\.session)
        }
        return visible
            .filter { $0.origin == .channel(channelID) }
            .sorted { $0.segmentIndex < $1.segmentIndex }
            .compactMap(\.session)
    }

    /// 枢纽会话段投影：与管理页可见段同集（枢纽活
    /// 动拼装的会话输入口径收编点；枢纽店本包不改
    /// 消费方式，本投影先行就位）
    public static func hubSessions(
        _ records: [SessionRecord]
    ) -> [ServerSession] {
        managementVisible(records)
    }
}
