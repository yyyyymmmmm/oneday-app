import Foundation
import OneDayCore

/// 条目行构建快照（§362）：ChatNativeRowRevision
/// 的条目侧入账字段原值全集——行构建增量备忘的
/// 验证真源。字段集与 entryBase 旧枚举逐项同集
/// （角色／正文／图数据两槽／引用四族／思考／工
/// 具卡与远端路径数据／回响三键／钉桩／反应／发
/// 送三态／创建时间）：捕获（capture）是字段读
/// 取单点、basePrefixRevision 是摘要枚举单点，
/// 两处同集由等价钉测逐字段敏感性把守——任一
/// 字段在条目上变更，快照必不等、备忘必失效重
/// 建，不存在「用旧行冒充新行」的路径（验证走
/// 全字段精确相等、无哈希碰撞面，比旧 fnv 摘要
/// 口径更严）
struct ChatEntryRevisionSnapshot: Equatable {
    let role: String
    let content: String
    let imageData: Data?
    let imageDatasData: Data?
    let quoteRole: String?
    let quoteContent: String?
    let feedPostID: String?
    let feedPostTitle: String?
    let feedPostBody: String?
    let feedPostSource: String?
    let ideaQuoteID: String?
    let ideaQuoteTitle: String?
    let ideaQuoteBody: String?
    let fileQuoteName: String?
    let fileQuotePath: String?
    let goalQuoteCategory: String?
    let reasoning: String?
    let reasoningSeconds: Double?
    let toolCardData: Data?
    let remoteImagePathsData: Data?
    let remoteFilePathsData: Data?
    let echoKey: String?
    let approvalKey: String?
    let traceKey: String?
    let traceEchoData: Data?
    let serverRowID: Int?
    let reactionsData: Data?
    let sendFailed: Bool
    let sendStateRaw: String?
    let deliveryState: String?
    let createdAt: Date

    /// 字段读取单点：条目现值逐项摘入快照（只读
    /// 属性、CoW 引用拷贝，不解码不哈希）
    static func capture(
        _ entry: ChatEntry
    ) -> ChatEntryRevisionSnapshot {
        ChatEntryRevisionSnapshot(
            role: entry.role,
            content: entry.content,
            imageData: entry.imageData,
            imageDatasData: entry.imageDatasData,
            quoteRole: entry.quoteRole,
            quoteContent: entry.quoteContent,
            feedPostID: entry.feedPostID,
            feedPostTitle: entry.feedPostTitle,
            feedPostBody: entry.feedPostBody,
            feedPostSource: entry.feedPostSource,
            ideaQuoteID: entry.ideaQuoteID,
            ideaQuoteTitle: entry.ideaQuoteTitle,
            ideaQuoteBody: entry.ideaQuoteBody,
            fileQuoteName: entry.fileQuoteName,
            fileQuotePath: entry.fileQuotePath,
            goalQuoteCategory: entry.goalQuoteCategory,
            reasoning: entry.reasoning,
            reasoningSeconds: entry.reasoningSeconds,
            toolCardData: entry.toolCardData,
            remoteImagePathsData: entry.remoteImagePathsData,
            remoteFilePathsData: entry.remoteFilePathsData,
            echoKey: entry.echoKey,
            approvalKey: entry.approvalKey,
            traceKey: entry.traceKey,
            traceEchoData: entry.traceEchoData,
            serverRowID: entry.serverRowID,
            reactionsData: entry.reactionsData,
            sendFailed: entry.sendFailed,
            sendStateRaw: entry.sendStateRaw,
            deliveryState: entry.deliveryState,
            createdAt: entry.createdAt
        )
    }

    /// 摘要枚举单点：entryBase 的条目侧前缀段
    /// （至 createdAt 为止）——与 entryBase 旧枚
    /// 举逐项同序同法（addText／addData／addReal
    /// 语义原样），环境尾段（分隔文案／未读分界
    /// 旗）不在此列、由 entryBase 在前缀后接续
    func basePrefixRevision() -> ChatNativeRowRevision {
        var revision = ChatNativeRowRevision()
        revision.addText(role)
        revision.addText(content)
        revision.addData(imageData)
        revision.addData(imageDatasData)
        revision.addText(quoteRole)
        revision.addText(quoteContent)
        revision.addText(feedPostID)
        revision.addText(feedPostTitle)
        revision.addText(feedPostBody)
        revision.addText(feedPostSource)
        revision.addText(ideaQuoteID)
        revision.addText(ideaQuoteTitle)
        revision.addText(ideaQuoteBody)
        revision.addText(fileQuoteName)
        revision.addText(fileQuotePath)
        revision.addText(goalQuoteCategory)
        revision.addText(reasoning)
        revision.addReal(reasoningSeconds)
        revision.addData(toolCardData)
        revision.addData(remoteImagePathsData)
        revision.addData(remoteFilePathsData)
        revision.addText(echoKey)
        revision.addText(approvalKey)
        revision.addText(traceKey)
        revision.addData(traceEchoData)
        // 台账 187：钉桩与反应镜像同列入账（字段
        // 枚举全量纪律）——与 entryBase 旧口径逐
        // 值同（serverRowID nil 折 0）
        revision.addCount(serverRowID ?? 0)
        revision.addData(reactionsData)
        revision.addFlag(sendFailed)
        revision.addText(sendStateRaw)
        revision.addText(deliveryState)
        revision.parts.append(
            .real(createdAt.timeIntervalSinceReferenceDate)
        )
        return revision
    }
}

/// 行构建增量备忘（§362，流畅度专项 S2）：把
/// nativeRows 每趟的行构建从「全量重算」改成
/// 「按行验证、只对变化行重算」——条目未变时，
/// entryBase 的全文哈希（正文／思考逐字节 FNV）
/// 与 parts 构建、facet 扫描派生（EntryScanMemo
/// 键组装的正文哈希）全部免付，只付一次字段快
/// 照的精确相等验证（成本与行数成正比、与文本
/// 量脱钩）；条目任一入账字段变更即快照不等、
/// 当行全量重建并换账。与行描述备忘（ChatNative-
/// RowDescriptorMemo）分工：彼缓存行描述成品
/// （戳判定在后段），本盒缓存行构建的条目侧产
/// 物（基段前缀＋facet 扫描派生），戳的组装材
/// 料在此先行增量化。趟末 prune 与描述备忘同
/// 纪律：只留本趟在席条目
@MainActor
final class ChatEntryRowBuildMemo {

    /// 一条目的已建产物：快照（验证真源）＋基段
    /// 前缀（行修订与备忘键共用）＋facet 扫描派
    /// 生（懒建：交付 id 集／路径集，纯函数于正
    /// 文＋远端图路径、随快照同失效）
    final class Products {
        let snapshot: ChatEntryRevisionSnapshot
        let prefixRevision: ChatNativeRowRevision
        var facetDeliveryIDs: [String]?
        var facetPaths: [String]?

        init(
            snapshot: ChatEntryRevisionSnapshot,
            prefixRevision: ChatNativeRowRevision
        ) {
            self.snapshot = snapshot
            self.prefixRevision = prefixRevision
        }
    }

    private var cache: [UUID: Products] = [:]
    /// 计数口供测试与探针读（验证命中／重建）
    private(set) var hitCount = 0
    private(set) var missCount = 0

    /// 验证单点：摘当前快照与账面比对——等即命
    /// 中直取产物；不等（首见／任一字段变更／同
    /// id 换对象）即按新快照重建前缀并换账。一
    /// 趟内同一条目只许在此验证一次：调用方取
    /// Products 后穿线给后续环节（基段组装／
    /// facet 摘要），不许同趟二次验证
    func products(
        for entry: ChatEntry
    ) -> Products {
        let snapshot = ChatEntryRevisionSnapshot.capture(entry)
        if let cached = cache[entry.id],
           cached.snapshot == snapshot {
            hitCount += 1
            return cached
        }
        missCount += 1
        let products = Products(
            snapshot: snapshot,
            prefixRevision: snapshot.basePrefixRevision()
        )
        cache[entry.id] = products
        return products
    }

    /// 行修订基段（与 ChatNativeRowRevision.
    /// entryBase 逐值同）：账面前缀＋环境尾段
    /// （分隔文案／未读分界旗）。products 入参
    /// 版供同趟已验证的调用方穿线
    func baseRevision(
        products: Products,
        dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> ChatNativeRowRevision {
        var revision = products.prefixRevision
        revision.addText(dividerText)
        revision.addFlag(showsUnreadDivider)
        return revision
    }

    func baseRevision(
        for entry: ChatEntry,
        dividerText: String?,
        showsUnreadDivider: Bool = false
    ) -> ChatNativeRowRevision {
        baseRevision(
            products: products(for: entry),
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
    }

    /// 条目行修订全量（与 ChatNativeRowRevision.
    /// entry 逐值同）：基段＋点亮旗＋样式键
    func entryRevision(
        for entry: ChatEntry,
        dividerText: String?,
        highlighted: Bool,
        styleKey: String,
        showsUnreadDivider: Bool = false
    ) -> ChatNativeRowRevision {
        var revision = baseRevision(
            for: entry,
            dividerText: dividerText,
            showsUnreadDivider: showsUnreadDivider
        )
        revision.addFlag(highlighted)
        revision.addText(styleKey)
        return revision
    }

    /// facet 扫描派生（与 entryFacetDigest 旧现
    /// 算逐值同）：交付 id 集与路径集只随条目内
    /// 容变、与 facet 活状态（展开／审批／文件／
    /// 解码态）无关——故随产物同缓存；活状态本
    /// 身仍由 entryFacetDigest 逐趟活读折入，不
    /// 在此列。products 入参版不重复验证（同趟
    /// 穿线）；for 入参版自带验证供独立调用
    /// nonisolated：合成器 facet 摘要在非隔离上
    /// 下文调用本口（量测键组装的同步路径）——本
    /// 函数只按纯函数结果回填 Products 的两懒置
    /// 槽，同值幂等写、无跨线程状态，Products 本
    /// 体的验证与换账仍只在 MainActor 的 products
    /// (for:) 单点
    nonisolated static func facetScanLists(
        products: Products,
        entry: ChatEntry
    ) -> (deliveryIDs: [String], paths: [String]) {
        if let deliveryIDs = products.facetDeliveryIDs,
           let paths = products.facetPaths {
            return (deliveryIDs, paths)
        }
        let scans = EntryScanMemo.scans(
            entryID: entry.id,
            content: entry.content,
            remoteImagePaths: entry.remoteImagePaths
        )
        let paths = EntryScanMemo.facetPaths(
            entryID: entry.id,
            content: entry.content,
            remoteImagePaths: entry.remoteImagePaths
        )
        products.facetDeliveryIDs = scans.delivery.deliveryIDs
        products.facetPaths = paths
        return (scans.delivery.deliveryIDs, paths)
    }

    func facetScanLists(
        for entry: ChatEntry
    ) -> (deliveryIDs: [String], paths: [String]) {
        Self.facetScanLists(
            products: products(for: entry), entry: entry
        )
    }

    /// 趟末清账：只留本趟在席条目（线程切换／行
    /// 删除后不留陈账；同 id 复现时快照验证仍兜
    /// 底、陈账无冒充路径）
    func prune(keeping entryIDs: Set<UUID>) {
        cache = cache.filter { entryIDs.contains($0.key) }
    }

    /// 测试读口：清计数不清缓存
    func resetCounts() {
        hitCount = 0
        missCount = 0
    }
}
