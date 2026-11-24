import Foundation
import SwiftUI
import OneDayCore

// MARK: - 变更集（DESIGN §374，换引擎步骤 1）

/// 变更集：喂入侧逐趟产出的离散变更——insert／
/// delete／update 三类行键集。形态照 Stream Chat
/// iOS 的 `[ListChange<ChatMessage>]`（数据层产出
/// 离散变更、列表只应用变更；施工图对位表 #1）：
/// 变更在喂入侧产生、单趟成本只随变更量不随总
/// 量。步骤 1 为影子期产物（只算不用、与旧路差
/// 集逐趟对账），步骤 2 起为控制器 applyChanges
/// 的输入
struct EntryChangeSet: Equatable {
    var inserted: Set<String> = []
    var deleted: Set<String> = []
    var updated: Set<String> = []
    /// §374.2：高-only 变更键（修订未变、高或临
    /// 界旗变）——旧路不构成重配、只走高度账落
    /// 写＋布局失效记账；新路 applyChanges 据此
    /// 局部落写高度账。与 updated 互斥（修订变
    /// 的行高由其落写承接）
    var heightChanged: Set<String> = []
    /// §374.2：续行相对序变（同键集重排）——增
    /// 量编辑无移动语义，控制器见此旗整笔走重
    /// 建路。喂入级事实（非路差）：两路同值
    var orderChanged: Bool = false

    /// 编辑集口径的空判（高-only 不入本判：其落
    /// 写走高度账、不经快照编辑）
    var isEmpty: Bool {
        inserted.isEmpty && deleted.isEmpty
            && updated.isEmpty
    }

    /// 变更集合成（§374.2）：本集相对基态 S、
    /// next 相对 S＋本集，合成相对 S 的等价变更
    /// 集——控制器冻结槽内两笔新路喂入在途合并
    /// 用（后到整笔覆盖会丢前笔的键级事实，合成
    /// 保全之）。规则：插后删＝相消；删后重插＝
    /// 更新＋序变旗（位置可能已移、控制器见旗
    /// 走重建路）；更新归并；高-only 取并集减去
    /// 已归插/删者；序变取或
    func composing(_ next: EntryChangeSet) -> EntryChangeSet {
        var result = EntryChangeSet()
        var newInserted = inserted
        var newDeleted = deleted
        var newUpdated = updated
        result.orderChanged = orderChanged
            || next.orderChanged
        for key in next.deleted {
            if newInserted.contains(key) {
                newInserted.remove(key)
            } else {
                newUpdated.remove(key)
                newDeleted.insert(key)
            }
        }
        for key in next.inserted {
            if newDeleted.contains(key) {
                newDeleted.remove(key)
                newUpdated.insert(key)
                result.orderChanged = true
            } else if !newInserted.contains(key)
                && !newUpdated.contains(key) {
                newInserted.insert(key)
            }
        }
        for key in next.updated {
            if !newInserted.contains(key)
                && !newDeleted.contains(key) {
                newUpdated.insert(key)
            }
        }
        result.inserted = newInserted
        result.deleted = newDeleted
        result.updated = newUpdated
        result.heightChanged = heightChanged
            .union(next.heightChanged)
            .subtracting(newInserted)
            .subtracting(newDeleted)
        return result
    }
}

/// 条目行验证基：nativeEntryRow 构建一行的判定
/// 材料全集——条目侧走 §362 快照精确相等（验证
/// 真源、全字段原值比对、无哈希碰撞面），环境
/// 侧为修订尾段的同列入账项（分隔文案／未读分
/// 界／来源集／点亮／样式键）；高与临界旗另列：
/// 高-only 变在旧路不构成重配（只走布局失效记
/// 账），变更集的 update 口径与此对齐；但行值
/// 缓存的喂入复用判据含高（见 Record 两级判定）
struct ChatFeedEntryBasis {
    let entryID: UUID
    let snapshot: ChatEntryRevisionSnapshot
    let dividerText: String?
    let showsUnreadDivider: Bool
    let sources: [MessageSource]
    let highlighted: Bool
    let styleKey: String
    let feedHeight: CGFloat
    let heightIsProvisional: Bool
}

// MARK: - 行值缓存（步骤 1）

/// 行值缓存：以条目身份为键，缓存上一趟的
/// ChatNativeRow 值对象与验证基——未变条目复用
/// 旧值对象、不重建（判据＝§362 快照精确相等＋
/// 环境尾段全等）。与既有两备忘分工：行构建备
/// 忘（§362）缓存构建产物、行描述备忘缓存成品
/// 戳判定；本盒是换引擎新路的行值真源，步骤 2
/// 起喂入直接取本盒行值。Record 为 class 形态：
/// 命中沿用同一对象（身份 === 可断言），修订级
/// 输入变才换账；高-only 变原地刷新行值（对象
/// 不换、高账更新）——与旧路「高变不重配」同义
@MainActor
final class ChatNativeRowValueCache {

    final class Record {
        let entryID: UUID
        var rowKey: String
        var row: ChatNativeRow
        var snapshot: ChatEntryRevisionSnapshot
        var dividerText: String?
        var showsUnreadDivider: Bool
        var sources: [MessageSource]
        var highlighted: Bool
        var styleKey: String
        var feedHeight: CGFloat
        var heightIsProvisional: Bool

        init(row: ChatNativeRow, basis: ChatFeedEntryBasis) {
            entryID = basis.entryID
            rowKey = row.key
            self.row = row
            snapshot = basis.snapshot
            dividerText = basis.dividerText
            showsUnreadDivider = basis.showsUnreadDivider
            sources = basis.sources
            highlighted = basis.highlighted
            styleKey = basis.styleKey
            feedHeight = basis.feedHeight
            heightIsProvisional = basis.heightIsProvisional
        }

        /// 修订级判定：快照＋环境尾段全等——等即
        /// 行渲染输入未变（与旧路修订差集同口径）
        func revisionInputsMatch(
            _ basis: ChatFeedEntryBasis
        ) -> Bool {
            snapshot == basis.snapshot
                && dividerText == basis.dividerText
                && showsUnreadDivider
                    == basis.showsUnreadDivider
                && sources == basis.sources
                && highlighted == basis.highlighted
                && styleKey == basis.styleKey
        }

        /// 高判定：修订级之外的喂入高与临界旗
        func heightInputsMatch(
            _ basis: ChatFeedEntryBasis
        ) -> Bool {
            feedHeight == basis.feedHeight
                && heightIsProvisional
                    == basis.heightIsProvisional
        }

        /// 原地刷新（修订级未变、高或行键变时）：
        /// 对象身份不变、行值与高账换现值
        func refresh(
            row: ChatNativeRow, basis: ChatFeedEntryBasis
        ) {
            rowKey = row.key
            self.row = row
            feedHeight = basis.feedHeight
            heightIsProvisional = basis.heightIsProvisional
        }
    }

    private var records: [UUID: Record] = [:]
    /// 计数口供测试与探针读（修订级沿用／换账）
    private(set) var reuseCount = 0
    private(set) var rebuildCount = 0

    func record(for entryID: UUID) -> Record? {
        records[entryID]
    }

    func noteReuse() {
        reuseCount += 1
    }

    /// 换账：新 Record 入账（首见／修订级变更）
    @discardableResult
    func store(
        row: ChatNativeRow, basis: ChatFeedEntryBasis
    ) -> Record {
        rebuildCount += 1
        let record = Record(row: row, basis: basis)
        records[basis.entryID] = record
        return record
    }

    /// 趟末清账：只留本趟在席条目（与行构建备忘
    /// 同纪律；同 id 复现时快照验证仍兜底）
    func prune(keeping entryIDs: Set<UUID>) {
        records = records.filter {
            entryIDs.contains($0.key)
        }
    }

    func removeAll() {
        records.removeAll()
    }

    /// 测试读口：清计数不清缓存
    func resetCounts() {
        reuseCount = 0
        rebuildCount = 0
    }
}

// MARK: - 影子对账账（步骤 1）

/// 影子对账账：变更集（新路）与旧路修订差集逐
/// 趟比对的诊断账——差异计数（按类累计键次）、
/// 首个差异键与类别，供测试与影子长跑读。比对
/// 口径：三类键集逐类对称差；旧路差集按
/// applyNow 现行定义复刻（键集差＋同键修订全量
/// 比较，见 ChatFeedChangeTracker.oldRoadChange-
/// Set）——触摸暂存是控制器时序件、非喂入差，
/// 不入本账（其候选集本体即修订差集）
@MainActor
final class ChatFeedShadowLedger {
    private(set) var passCount = 0
    private(set) var diffPassCount = 0
    private(set) var diffCount = 0
    private(set) var firstDiffKey: String?
    private(set) var firstDiffKind: String?

    func record(
        changeSet: EntryChangeSet,
        oldRoad: EntryChangeSet
    ) {
        passCount += 1
        var diffs: [(kind: String, key: String)] = []
        for key in changeSet.inserted
            .symmetricDifference(oldRoad.inserted) {
            diffs.append((kind: "inserted", key: key))
        }
        for key in changeSet.deleted
            .symmetricDifference(oldRoad.deleted) {
            diffs.append((kind: "deleted", key: key))
        }
        for key in changeSet.updated
            .symmetricDifference(oldRoad.updated) {
            diffs.append((kind: "updated", key: key))
        }
        guard !diffs.isEmpty else { return }
        diffPassCount += 1
        diffCount += diffs.count
        if firstDiffKey == nil,
           let first = diffs.sorted(by: {
               ($0.kind, $0.key) < ($1.kind, $1.key)
           }).first {
            firstDiffKey = first.key
            firstDiffKind = first.kind
        }
    }

    func reset() {
        passCount = 0
        diffPassCount = 0
        diffCount = 0
        firstDiffKey = nil
        firstDiffKind = nil
    }
}

// MARK: - 变更集追踪器（步骤 1）

/// 变更集追踪器：nativeRows 每趟的影子引擎——
/// 条目行经行值缓存判定（快照＋环境尾段），非条
/// 目行（直播／工具组／回告／审批区／空状态）走
/// 修订比较（其修订即旧路判据本体、逐值同）；同
/// 趟产出 EntryChangeSet 并与旧路差集对账入影子
/// 账。开关关时 ChatView 零调用、本类零状态；开
/// 关开时只算不用——喂入仍走旧路行数组、控制器
/// 一行不动（步骤 1 出口＝钉测语料差异清零）
@MainActor
final class ChatFeedChangeTracker {
    let rowValueCache = ChatNativeRowValueCache()
    let shadowLedger = ChatFeedShadowLedger()
    private(set) var lastChangeSet = EntryChangeSet()
    private(set) var lastOldRoadChangeSet =
        EntryChangeSet()

    /// 本趟待消费的条目验证基（nativeEntryRow 构
    /// 建时逐行登记、ingest 时整趟消费后清空）
    private var pendingBases: [UUID: ChatFeedEntryBasis] =
        [:]
    /// 上趟喂入全集的修订账（旧路差集复刻的输入）
    private var previousRevisions:
        [String: ChatNativeRowRevision] = [:]
    private var previousKeys: Set<String> = []
    /// §374.2：上趟喂入序与高账——序变与高-only
    /// 的比对基（高账以行键存（高，临界旗））
    private var previousKeyOrder: [String] = []
    private var previousHeights:
        [String: (height: CGFloat, provisional: Bool)] =
        [:]

    func noteEntryBasis(_ basis: ChatFeedEntryBasis) {
        pendingBases[basis.entryID] = basis
    }

    /// 一趟喂入的影子消费：产出变更集＋对账＋换账
    @discardableResult
    func ingest(
        rows: [ChatNativeRow]
    ) -> EntryChangeSet {
        let bases = pendingBases
        pendingBases.removeAll()
        let newKeySet = Set(rows.map(\.key))
        var changeSet = EntryChangeSet()
        changeSet.inserted =
            newKeySet.subtracting(previousKeys)
        changeSet.deleted =
            previousKeys.subtracting(newKeySet)
        let continuing =
            newKeySet.intersection(previousKeys)
        // §374.2：高-only 与序变（喂入级事实）——
        // 高变以（高，临界旗）逐键与上趟喂入值比
        // 对（条目行 basis 喂入高与行高同值、非条
        // 目行同理，认行值本体）；序变以续行键在
        // 两趟序中的相对序比对（增删不构成序变）
        var heightDiffs: Set<String> = []
        for row in rows where continuing.contains(row.key) {
            if let previous = previousHeights[row.key],
               (previous.height != row.height
                || previous.provisional
                    != row.heightIsProvisional) {
                heightDiffs.insert(row.key)
            }
        }
        let orderChanged = previousKeyOrder.filter {
            newKeySet.contains($0)
        } != rows.map(\.key).filter {
            previousKeys.contains($0)
        }
        var seenEntryIDs: Set<UUID> = []
        for row in rows {
            if let entryID = row.entryID,
               let basis = bases[entryID] {
                seenEntryIDs.insert(entryID)
                if let record = rowValueCache.record(
                    for: entryID
                ) {
                    if record.revisionInputsMatch(basis) {
                        rowValueCache.noteReuse()
                        // 修订级未变：不入 update（行
                        // 键变由键集差承接）；高或行
                        // 键变时原地刷新行值备步骤 2
                        // 喂入取用
                        if record.rowKey != row.key
                            || !record.heightInputsMatch(
                                basis
                            )
                            || record.row.revision
                                != row.revision {
                            record.refresh(
                                row: row, basis: basis
                            )
                        }
                    } else {
                        if continuing.contains(row.key) {
                            changeSet.updated
                                .insert(row.key)
                        }
                        rowValueCache.store(
                            row: row, basis: basis
                        )
                    }
                } else {
                    // 首见条目：键新入列者插入集已承
                    // 接；键续行而条目首见者＝落定同
                    // 键换代（§247：直播行键被落定条
                    // 目沿用、条目身份本趟初现）——旧
                    // 路以同键修订差判重构，本路同口
                    // 径补入更新集（§374.2 步骤 2 实
                    // 查缺口：不补则落定行永不重构、
                    // 停在直播内容）
                    if continuing.contains(row.key),
                       let previous =
                        previousRevisions[row.key],
                       previous != row.revision {
                        changeSet.updated
                            .insert(row.key)
                    }
                    rowValueCache.store(
                        row: row, basis: basis
                    )
                }
            } else if continuing.contains(row.key),
                      let previous =
                        previousRevisions[row.key],
                      previous != row.revision {
                changeSet.updated.insert(row.key)
            }
        }
        changeSet.heightChanged = heightDiffs
            .subtracting(changeSet.updated)
        changeSet.orderChanged = orderChanged
        var oldRoad = oldRoadChangeSet(
            rows: rows, continuing: continuing,
            inserted: changeSet.inserted,
            deleted: changeSet.deleted
        )
        // 高-only 与序变是喂入级事实、非路差：两
        // 集同值（影子账只比对插/删/更三集）
        oldRoad.heightChanged = changeSet.heightChanged
        oldRoad.orderChanged = orderChanged
        shadowLedger.record(
            changeSet: changeSet, oldRoad: oldRoad
        )
        lastChangeSet = changeSet
        lastOldRoadChangeSet = oldRoad
        previousRevisions = Dictionary(
            uniqueKeysWithValues: rows.map {
                ($0.key, $0.revision)
            }
        )
        previousKeys = newKeySet
        previousHeights = Dictionary(
            uniqueKeysWithValues: rows.map {
                ($0.key, (height: $0.height,
                          provisional:
                            $0.heightIsProvisional))
            }
        )
        previousKeyOrder = rows.map(\.key)
        rowValueCache.prune(keeping: seenEntryIDs)
        return changeSet
    }

    /// 旧路差集（applyNow 现行定义的喂入级复刻）：
    /// 键集差＋同键修订全量比较——修订差即
    /// applyNow 的 revisionMismatchKeys；触摸暂存
    /// 留账的候选本体同出此集、其分流是时序件不
    /// 入差集
    private func oldRoadChangeSet(
        rows: [ChatNativeRow],
        continuing: Set<String>,
        inserted: Set<String>,
        deleted: Set<String>
    ) -> EntryChangeSet {
        var set = EntryChangeSet()
        set.inserted = inserted
        set.deleted = deleted
        for row in rows where continuing.contains(row.key) {
            if let previous = previousRevisions[row.key],
               previous != row.revision {
                set.updated.insert(row.key)
            }
        }
        return set
    }

    func reset() {
        pendingBases.removeAll()
        previousRevisions.removeAll()
        previousKeys.removeAll()
        previousKeyOrder.removeAll()
        previousHeights.removeAll()
        lastChangeSet = EntryChangeSet()
        lastOldRoadChangeSet = EntryChangeSet()
        rowValueCache.removeAll()
        shadowLedger.reset()
    }
}
