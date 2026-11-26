import Foundation
import OneDayCore
import UIKit

/// 条目行高输入快照（§331）：合成器核心读的条
/// 目字段全集（值副本）——ChatEntry 是主线程类，
/// 后台量测不得直读；快照后核心只碰值。图片数
/// 据只为本地图解码判定而带（写时复制、缓冲共
/// 享不拷字节）
struct ChatEntryHeightSnapshot {
    let id: UUID
    let role: String
    let content: String
    let createdAt: Date
    let sendFailed: Bool
    let isPendingSend: Bool
    /// §414 增补（断网发送态规格 5.3）：未确认发送
    /// 位——与条目谓词 isUnconfirmedSend 同源派生
    /// （快照点单点取值），原生面 cell 侧消费同值
    /// 决定气泡浅色态，不许另写一份判定
    let isUnconfirmedSend: Bool
    let quote: MessageQuote?
    let sourceQuote: SourceQuote?
    let reasoning: String?
    let toolCard: ToolCard?
    let remoteImagePaths: [String]
    let remoteFilePaths: [String]
    let imageDatas: [Data]
    let echoKey: String?
    let approvalKey: String?
    let traceKey: String?
    let traceEcho: TraceEchoSnapshot?
    /// 台账 187：反应镜像（行高 facet——有反应即行
    /// 高多一笔 pill 悬出预留；值在条目构建时同步已
    /// 知、无异步翻转，同 toolCard/remoteImagePaths
    /// 的 facet 纪律）
    let reactions: [MessageReaction]
    /// §432：AI 反应开关的快照值（主线程快照时点
    /// 读 Core 特性键，与呈现层 @AppStorage 同源同
    /// 值）——预留判定只认快照不活读（facet 纪
    /// 律）；合成器经 hasReactionChrome 消费
    let aiSelfReactionsEnabled: Bool

    /// 反应铬件在场（§432）：pill（own 段）或角标
    /// （agent 段且开关开）任一在场——判定单源在
    /// Core AISelfReactionDecision，呈现层同判
    var hasReactionChrome: Bool {
        AISelfReactionDecision.hasVisibleChrome(
            reactions: reactions,
            featureEnabled: aiSelfReactionsEnabled
        )
    }
    /// D4（§349）：本条所属轮的聚合来源（呈现层派
    /// 生、拼装时注入）——非条目本体字段：来源的数
    /// 据源是同轮工具条目的卡（工具行原文单源），
    /// 快照只携派生结果供合成器定高
    let sources: [MessageSource]

    init(
        _ entry: ChatEntry, sources: [MessageSource] = [],
        aiSelfReactionsEnabled: Bool
            = ChatReactionsAISelfFeature.isEnabled()
    ) {
        id = entry.id
        role = entry.role
        content = entry.content
        createdAt = entry.createdAt
        sendFailed = entry.sendFailed
        isPendingSend = entry.isPendingSend
        isUnconfirmedSend = entry.isUnconfirmedSend
        quote = entry.quote
        sourceQuote = entry.sourceQuote
        reasoning = entry.reasoning
        toolCard = entry.toolCard
        remoteImagePaths = entry.remoteImagePaths
        remoteFilePaths = entry.remoteFilePaths
        imageDatas = entry.allImageDatas
        echoKey = entry.echoKey
        approvalKey = entry.approvalKey
        traceKey = entry.traceKey
        traceEcho = entry.traceEcho
        reactions = entry.reactions
        self.aiSelfReactionsEnabled = aiSelfReactionsEnabled
        self.sources = sources
    }
}

/// 行高 facet 快照（§331）：合成器核心的一切外
/// 部读（账本展开覆盖/审批详情/宿主审批锚态/备
/// 注/裁决中/文件存在性与大小/交付 meta 与封面
/// 形态/本地图解码）在主线程先落为值；核心据此
/// 成为纯函数（值进→高出），可在量测台后台队
/// 列整行执行。快照枚举与 §330 备忘键的 facet
/// 摘要同源（摘要折什么、快照取什么——键与工
/// 单永远同值，不会键新值旧）
struct ChatNativeRowFacets {
    var expansionOverrides: [String: Bool] = [:]
    var approvalDetails: [String: ApprovalDetailState] = [:]
    var anchorStates: [String: ApprovalAnchor.RowState] = [:]
    var cardNotes: [String: String] = [:]
    var decidingIDs: Set<String> = []
    /// 存在性：键缺＝未验证（与 existence(for:)
    /// 回 nil 同义）
    var fileExistences: [String: FileMetadataStore.Existence] = [:]
    var fileSizes: [String: Int64] = [:]
    var deliveryMetas: [String: DeliveryStore.MetaResult] = [:]
    /// 封面形态（交付卡高唯一读的缓存合成值，快
    /// 照点按现行公式先算定）
    var deliveryCoverForms: [String: Bool] = [:]
    /// 本地图解码成败（与条目 imageDatas 同序）
    var localImageDecoded: [Bool] = []
    /// 审批区：ready 时的遍历集（记录本体全量
    /// ＋锚定集＋已决行 id 集；活卡/余数的队列
    /// 派生在合成器核心经 ApprovalZoneQueue
    /// 做）；nil＝非 ready
    var zoneRecords: [WriteGateRecord]?
    /// 选择框行高输入（总表 203／§441）：键＝条
    /// 目 id；值由 ChatView 按覆盖层＋线程尾位规
    /// 则派生后经快照器注入（与 sources 同为呈现
    /// 层派生 facet）；键缺＝无卡、零增量
    var optionsCards: [UUID: OptionsCardHeightInput] = [:]
    /// 凭据卡行高输入（0.51.2）：键＝条目 id；值
    /// 为该行全部凭据卡（块卡＋标记兜底卡/灰行）
    /// 的输入列，由 ChatView 按覆盖层＋请求列表
    /// 派生后经快照器注入（与 optionsCards 同为
    /// 呈现层派生 facet）；键缺＝无卡、零增量
    var vaultCards: [UUID: [VaultCardHeightInput]] = [:]
    var zoneAnchoredIDs: Set<String> = []
    var zoneResolvedLineIDs: [String] = []
    /// 第 6 项：失败条目的分类成因快照（供后台量测
    /// 与同步合成同源读取 SendFailureCopy 行高）
    var failureKinds: [UUID: SendFailureKind] = [:]
}

/// facet 快照器（§331）：主线程执行——把合成器
/// 核心将读的外部值逐项落进快照。枚举与合成器
/// 读点对账（漏取一项＝后台算出旧高，故条目集
/// 逐 facet 与 ChatNativeRowHeight 的摘要枚举同
/// 构、且有「快照核心高＝现行合成高」对拍测试
/// 钉住，见 ChatNativeMeasureDeskTests）
enum ChatNativeRowFacetSnapshotter {
    @MainActor
    static func entryFacets(
        for entry: ChatEntry,
        ledger: ChatRowStateLedger,
        hubStore: AgentHubStore,
        outboxRetry: OutboxRetryStore? = nil,
        optionsCard: OptionsCardHeightInput? = nil,
        vaultCards: [VaultCardHeightInput] = []
    ) -> ChatNativeRowFacets {
        var facets = ChatNativeRowFacets()
        if entry.sendFailed,
           let kind = outboxRetry?.record(for: entry.id)?
            .lastFailureKind {
            facets.failureKinds[entry.id] = kind
        }
        if let optionsCard {
            facets.optionsCards[entry.id] = optionsCard
        }
        if !vaultCards.isEmpty {
            facets.vaultCards[entry.id] = vaultCards
        }
        recordExpansion(
            ledger,
            key: ChatRowStateKeys.reasoningEntry(entry.id),
            into: &facets
        )
        recordExpansion(
            ledger,
            key: ChatRowStateKeys.toolEntry(entry.id),
            into: &facets
        )
        recordExpansion(
            ledger,
            key: ChatRowStateKeys.sourcesEntry(entry.id),
            into: &facets
        )
        if entry.role == "user" {
            facets.localImageDecoded = entry
                .allImageDatas.indices.map { index in
                    LocalImageStore.shared.image(
                        entryID: entry.id, index: index,
                        data: entry.allImageDatas[index]
                    ) != nil
                }
            for rawPath in entry.remoteFilePaths {
                let split = FileLineAnchor.split(
                    pathWithAnchor: rawPath
                )
                recordFileState(split.path, into: &facets)
            }
        } else if entry.traceKey == nil
            && entry.echoKey == nil {
            let scans = EntryScanMemo.scans(
                entryID: entry.id,
                content: entry.content,
                remoteImagePaths: entry.remoteImagePaths
            )
            for deliveryID in scans.delivery.deliveryIDs {
                recordDelivery(deliveryID, into: &facets)
            }
            var paths = Set<String>()
            paths.formUnion(scans.media.imagePaths)
            paths.formUnion(
                scans.inlineCandidates.map(\.path)
            )
            paths.formUnion(scans.standalonePaths)
            let wholePathRef = FileRefDetector
                .wholeMessagePath(in: scans.media.text)
            if let wholePathRef {
                paths.insert(wholePathRef.path)
            }
            let fileRefs = FileRefDetector
                .detectStandaloneAnchored(
                    in: entry.content,
                    excluding: entry.remoteImagePaths
                        + scans.media.imagePaths
                        + scans.inlineCandidates
                            .map(\.path)
                        + (wholePathRef.map { [$0.path] }
                            ?? [])
                )
            paths.formUnion(fileRefs.map(\.path))
            for path in paths {
                recordFileState(path, into: &facets)
            }
        } else {
            // 台账 196（§335）：系统锚定行（留痕回
            // 响/委派回响）跳过助手扫描支——其行高
            // 在 entryHeightCore 先行支返回、文件/
            // 交付 facet 从不被读；本支原形态另跑
            // 一趟未备忘的 detectStandaloneAnchored
            // 全文扫（§333 已注的热路径残余全扫），
            // 对锚定行纯浪费、本次摘除（展开态记录
            // 在支外、照旧）
        }
        if entry.approvalKey != nil {
            let recordID = ApprovalAnchor.recordID(
                fromKey: entry.approvalKey ?? ""
            ) ?? ""
            facets.anchorStates[recordID] =
                hubStore.anchorRowState(recordID: recordID)
            facets.approvalDetails[recordID] =
                ledger.approvalDetail(for: recordID)
            if let note = hubStore.cardNotes[recordID] {
                facets.cardNotes[recordID] = note
            }
            if hubStore.decidingIDs.contains(recordID) {
                facets.decidingIDs.insert(recordID)
            }
        }
        return facets
    }

    @MainActor
    static func groupFacets(
        cards: [ToolCard], groupKey: String,
        ledger: ChatRowStateLedger
    ) -> ChatNativeRowFacets {
        var facets = ChatNativeRowFacets()
        recordExpansion(ledger, key: groupKey, into: &facets)
        for card in cards {
            recordExpansion(
                ledger,
                key: ChatRowStateKeys.toolGroupCard(
                    groupKey: groupKey, cardID: card.id
                ),
                into: &facets
            )
        }
        return facets
    }

    @MainActor
    static func zoneFacets(
        ledger: ChatRowStateLedger,
        hubStore: AgentHubStore
    ) -> ChatNativeRowFacets {
        var facets = ChatNativeRowFacets()
        guard case .ready(let records)
            = hubStore.approvalState
        else { return facets }
        facets.zoneRecords = records
        facets.zoneAnchoredIDs = hubStore.anchoredRecordIDs
        facets.zoneResolvedLineIDs =
            hubStore.resolvedLines.map(\.id)
        // D10 定版②：区高只读活卡一张的详情/备
        // 注/裁决中（与摘要、合成同口径，§331 快
        // 照纪律）——其余待批已收纳进计数行、无
        // 卡面读数，不入快照
        let queue = ApprovalZoneQueue.derive(
            recordIDs: records.map(\.id),
            anchoredIDs: hubStore.anchoredRecordIDs
        )
        if let activeID = queue.activeRecordID,
           let record = records.first(
               where: { $0.id == activeID }
           ) {
            facets.approvalDetails[record.id] =
                ledger.approvalDetail(for: record.id)
            if let note = hubStore.cardNotes[record.id] {
                facets.cardNotes[record.id] = note
            }
            if hubStore.decidingIDs.contains(record.id) {
                facets.decidingIDs.insert(record.id)
            }
        }
        return facets
    }

    // MARK: - 记录助手

    @MainActor
    private static func recordExpansion(
        _ ledger: ChatRowStateLedger, key: String,
        into facets: inout ChatNativeRowFacets
    ) {
        if let value = ledger.expansionOverride(for: key) {
            facets.expansionOverrides[key] = value
        }
    }

    @MainActor
    private static func recordFileState(
        _ path: String,
        into facets: inout ChatNativeRowFacets
    ) {
        if let existence = FileMetadataStore.shared
            .existence(for: path) {
            facets.fileExistences[path] = existence
        }
        if let size = FileMetadataStore.shared
            .metadata(for: path)?.size {
            facets.fileSizes[path] = size
        }
    }

    @MainActor
    private static func recordDelivery(
        _ id: String,
        into facets: inout ChatNativeRowFacets
    ) {
        guard let result = DeliveryStore.shared
            .metaResult(for: id)
        else { return }
        facets.deliveryMetas[id] = result
        if case .loaded(let meta) = result {
            // §407：封面形态只认登记旗（与活读
            // facetDeliveryCoverForm 同公式单源）——
            // 缓存到达态不进快照，免得工单量测与同
            // 步合成在缓存时序下分家
            facets.deliveryCoverForms[id] =
                meta.cover.cover
        }
    }
}
