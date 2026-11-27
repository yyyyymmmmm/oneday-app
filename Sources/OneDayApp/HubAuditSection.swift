import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页审核段（§434 新格，对位参照大头态盾格）：
/// 授权账本＋审批记录——数据全走真回读：授权清单
/// ＝GET /v1/grants（能力 #12，exec 命令授权＋写闸
/// 规则只读投影两源拼合，AgentHubStore.loadGrants
/// 承接）；审批记录＝写闸决定账（decisionHistory，
/// 与待批同轮拉取）＋本进程就地裁决结果行。exec
/// 授权可在此撤销（POST /v1/grants/revoke，终局以
/// 回读为准）；写闸规则的撤销仍归设置·权限区既有
/// 规则面，本段只读呈现、不新造写路。待审批的裁
/// 决仍只在聊天界面（§155 口径不变），本段只给计
/// 数与去处。
/// §477（2026-11-24 全抄）：授权清单与审批记录合
/// 并为单段「审核记录」——一段一表、时间倒序混排，
/// 两类靠行元信息的处置词区分（授权＝「始终允许 ·
/// …」、裁决＝「已批准/已按规则放行/已驳回 · …」）；
/// 段头改 HubSectionHeader 令牌件（系统 Section 头
/// 的灰字灰带退役）；行三级全人话化——标题 20
/// semibold 主黑、说明 16 次级灰、元信息 15 三级
/// 灰，scope/op 英文原文不上列表（映射单源 Hub-
/// AuditText＋已决头条 ApprovalHeadline，原文只进
/// 详情）；行左图标改无底盘小字形（≈20，对参照审
/// 核帧；与工作行圆盘勿混同）。待批段保留置于记
/// 录段上方（偏离登记：裁决在对话内、计数须常驻
/// 可见，§477 审计 §5 已录）。
/// §493 起段末增「审批规则」入口（规则
/// 页自设置迁回本段，改判 §244）。
struct HubAuditSection: View {
    let hubStore: AgentHubStore

    /// 待撤销的授权（HIG 全过第一波）：撤销是破坏
    /// 性动作——旧形态 .bordered 小钮点按即撤、无确
    /// 认无后果说明；改走确认门（与技能商店卸载确认
    /// 同式：destructive 角色＋后果文案）
    @State private var pendingRevoke: AuditEntry?
    @State private var auditSnapshotCache = AuditSnapshotCache()
    @State private var expandedGroupIDs: Set<String> = []

    private final class AuditSnapshotCache {
        private var key: String?
        private var cached: [AuditEntry] = []

        func entries(
            grantsState: AgentHubStore.GrantsState,
            decisionHistory: [WriteGateDecisionRecord],
            resolvedLines: [ApprovalResolvedLine],
            activityGroups: [WriteGateActivityGroup]?
        ) -> [AuditEntry] {
            let grantCount: Int
            let grantFirst: String
            if case .ready(let resp) = grantsState {
                grantCount = resp.grants.count
                grantFirst = resp.grants.first?.grantKey ?? ""
            } else {
                grantCount = -1
                grantFirst = ""
            }
            let groupsCount = activityGroups?.count ?? -1
            let groupsFirst = activityGroups?.first.map { "\($0.id)|\($0.updatedAt?.timeIntervalSince1970 ?? 0)" } ?? ""
            let fingerprint = "\(grantCount)|\(grantFirst)|\(decisionHistory.count)|\(decisionHistory.first?.id ?? "")|\(resolvedLines.count)|\(resolvedLines.first?.id ?? "")|\(groupsCount)|\(groupsFirst)"
            if fingerprint == key {
                return cached
            }
            var entries: [AuditEntry] = []
            if case .ready(let response) = grantsState {
                entries += response.grants.map(AuditEntry.grant)
            }
            // 分组覆盖逻辑：组内 decided 成员的 id 集
            let coveredDecisionIDs: Set<String>
            if let groups = activityGroups {
                coveredDecisionIDs = Set(
                    groups.flatMap { group in
                        group.records.filter { $0.state == "decided" }.map(\.id)
                    }
                )
                entries += groups.map(AuditEntry.activityGroup)
            } else {
                coveredDecisionIDs = []
            }
            // 已决记录：不在覆盖集中的才出平铺行
            let decisionIDs = Set(decisionHistory.map(\.id))
            entries += decisionHistory
                .filter { !coveredDecisionIDs.contains($0.id) }
                .map(AuditEntry.decision)
            entries += resolvedLines
                .filter { !decisionIDs.contains($0.id) }
                .map(AuditEntry.resolved)
            let sorted = entries.enumerated()
                .sorted { a, b in
                    switch (a.element.sortDate, b.element.sortDate) {
                    case let (x?, y?):
                        return x != y ? x > y : a.offset < b.offset
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return a.offset < b.offset
                    }
                }
                .map(\.element)
            key = fingerprint
            cached = sorted
            return sorted
        }
    }

    var body: some View {
        List {
            pendingSection
            recordsSection
            rulesSection
        }
        .listStyle(.plain)
        .task {
            await hubStore.loadGrants()
        }
        .confirmationDialog(
            "撤销这条授权？",
            isPresented: Binding(
                get: { pendingRevoke != nil },
                set: { if !$0 { pendingRevoke = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("撤销", role: .destructive) {
                if let entry = pendingRevoke,
                   case .grant(let grant) = entry {
                    pendingRevoke = nil
                    Task { await hubStore.revokeGrant(grant) }
                }
            }
            Button("取消", role: .cancel) { pendingRevoke = nil }
        } message: {
            if let entry = pendingRevoke {
                Text("「\(title(for: entry))」撤销后立即失效，之后同类操作需要重新批准。")
            }
        }
    }

    // MARK: - 需要审核（实时待批，审批后自动进入下方审核记录）

    @ViewBuilder
    private var pendingSection: some View {
        Section {
            switch hubStore.approvalState {
            case .loading:
                ProgressView()
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
            case .bridgeUnavailable:
                quietRow("审批通道未接通，暂时无法读取待审批")
            case .gateDisabled:
                quietRow("写入审批尚未启用")
            case .failed(let message):
                quietRow(message)
            case .ready(let records) where records.isEmpty:
                quietRow("当前没有待审批")
            case .ready(let records):
                ForEach(records) { record in
                    ChatApprovalCard(
                        store: hubStore,
                        record: record
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(rowInsets)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, OneDayMetrics.spacingXS)
                }
            }
        } header: {
            Text("当前待审批")
                .font(.system(
                    size: OneDayMetrics.hubTitleSize,
                    weight: .semibold
                ))
                .foregroundStyle(Palette.ink)
                .textCase(nil)
        }
    }

    // MARK: - 审核记录（授权＋裁决合并单段）

    /// 合并行模型：授权（常设）与裁决（已决记录＋就
    /// 地结果行）三源归一，呈现层只认本枚举
    private enum AuditEntry: Identifiable {
        case grant(GrantEntry)
        case decision(WriteGateDecisionRecord)
        case resolved(ApprovalResolvedLine)
        case activityGroup(WriteGateActivityGroup)

        var id: String {
            switch self {
            case .grant(let entry): return "grant:" + entry.grantKey
            case .decision(let record): return "decision:" + record.id
            case .resolved(let line): return "resolved:" + line.id
            case .activityGroup(let group): return "group:" + group.id
            }
        }

        /// 排序时刻：授权取回读到的授予时刻（写闸授
        /// 权恒 nil——投影无此字段，不编造）；裁决取
        /// 落定时刻；就地行取裁决当时；组取 updatedAt
        var sortDate: Date? {
            switch self {
            case .grant(let entry): return entry.grantedAt
            case .decision(let record): return record.decidedAt
            case .resolved(let line): return line.at
            case .activityGroup(let group): return group.updatedAt
            }
        }
    }

    private var mergedEntries: [AuditEntry] {
        auditSnapshotCache.entries(
            grantsState: hubStore.grantsState,
            decisionHistory: hubStore.decisionHistory,
            resolvedLines: hubStore.resolvedLines,
            activityGroups: hubStore.activityGroups
        )
    }

    @ViewBuilder
    private var recordsSection: some View {
        let entries = mergedEntries
        Section {
            switch hubStore.grantsState {
            case .loading:
                if entries.isEmpty {
                    ProgressView()
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                }
            case .unavailable:
                quietRow("授权清单没读出来，可能是网络或服务暂时没响应")
            case .ready(let response):
                if response.partial {
                    quietRow("有一边没读全，下面的清单可能不完整")
                }
                if let note = hubStore.grantsNote {
                    quietRow(note)
                }
            }
            if !entries.isEmpty {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            } else if case .ready = hubStore.grantsState {
                quietRow("暂无审批记录")
            }
        } header: {
            Text("审批记录")
                .font(.system(
                    size: OneDayMetrics.hubTitleSize,
                    weight: .semibold
                ))
                .foregroundStyle(Palette.ink)
                .textCase(nil)
        }
    }

    // MARK: - 合并行（三级人话）

    @ViewBuilder
    private func entryRow(_ entry: AuditEntry) -> some View {
        if case .activityGroup(let group) = entry {
            groupRow(group)
        } else {
            regularEntryRow(entry)
        }
    }

    private func regularEntryRow(_ entry: AuditEntry) -> some View {
        HStack(
            alignment: .top,
            spacing: OneDayMetrics.spacingSM
        ) {
            rowGlyph(
                systemImage: glyphName(for: entry),
                tint: glyphTint(for: entry)
            )
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(title(for: entry))
                    .font(.system(
                        size: OneDayMetrics.hubTitleSize,
                        weight: .semibold
                    ))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let description = description(for: entry) {
                    Text(description)
                        // §500：副题 16 → 15（rowSubtitle）
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Text(meta(for: entry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if case .grant(let grant) = entry,
               grant.source == .exec {
                Button("撤销") {
                    pendingRevoke = entry
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                    hubStore.revokingGrantKeys
                        .contains(grant.grantKey)
                )
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    private func glyphName(for entry: AuditEntry) -> String {
        switch entry {
        case .grant(let grant):
            return grant.source == .exec
                ? "terminal" : "checkmark.shield"
        case .decision(let record):
            return record.decision == "approved"
                ? "checkmark" : "xmark"
        case .resolved(let line):
            return line.outcome.isPositive ? "checkmark" : "xmark"
        case .activityGroup(let group):
            switch group.status {
            case "pending": return "clock"
            case "failed": return "xmark"
            default: return "checkmark"
            }
        }
    }

    private func glyphTint(for entry: AuditEntry) -> Color {
        switch entry {
        case .grant:
            return Palette.inkSecondary
        case .decision(let record):
            return record.decision == "approved"
                ? Palette.success : Palette.danger
        case .resolved(let line):
            return line.outcome.isPositive
                ? Palette.success : Palette.danger
        case .activityGroup(let group):
            switch group.status {
            case "pending": return Palette.inkSecondary
            case "failed": return Palette.danger
            default: return Palette.success
            }
        }
    }

    private func title(for entry: AuditEntry) -> String {
        switch entry {
        case .grant(let grant):
            return HubAuditText.grantTitle(grant)
        case .decision(let record):
            // 已决头条走 ApprovalHeadline 单源（与待
            // 批卡同模板），summary 英文原串不上列表
            return record.headline
        case .resolved(let line):
            // 就地行 summary 即裁决当时的人话头条
            return line.summary
        case .activityGroup(let group):
            // 组头条＝服务端派生的人话标题（title_human）
            return group.titleHuman
        }
    }

    private func description(for entry: AuditEntry) -> String? {
        switch entry {
        case .grant(let grant):
            return HubAuditText.grantDescription(grant)
        case .decision(let record):
            return HubAuditText.decisionDescription(record)
        case .resolved:
            return nil
        case .activityGroup(let group):
            return group.preview
        }
    }

    private func meta(for entry: AuditEntry) -> String {
        switch entry {
        case .grant(let grant):
            return HubAuditText.grantMeta(grant)
        case .decision(let record):
            return decisionMeta(record)
        case .resolved(let line):
            return line.outcome.label + " · "
                + ApprovalTimeText.relative(line.at)
        case .activityGroup(let group):
            return groupMeta(group)
        }
    }

    private func decisionMeta(
        _ record: WriteGateDecisionRecord
    ) -> String {
        var head = record.decision == "approved"
            ? L10n.string("已批准") : L10n.string("已驳回")
        if record.viaRule != nil {
            head = L10n.string("已按规则放行")
        }
        guard let decidedAt = record.decidedAt else { return head }
        return head + " · " + ApprovalTimeText.relative(decidedAt)
    }

    // MARK: - 分组动态卡（任务级聚合，展开看每笔）

    /// 组元信息：汇总状态词＋笔数＋相对时间（组内最新
    /// 活动时刻）；待批计数单列，不许藏进总数里
    private func groupMeta(_ group: WriteGateActivityGroup) -> String {
        var parts: [String] = []
        switch group.status {
        case "pending":
            parts.append(L10n.string("待批"))
        case "failed":
            parts.append(L10n.string("有驳回"))
        default:
            parts.append(L10n.string("已完成"))
        }
        if group.counts.total > 1 {
            parts.append("共 \(group.counts.total) 笔")
        }
        if group.counts.pending > 0 {
            parts.append("待批 \(group.counts.pending)")
        }
        if let updatedAt = group.updatedAt {
            parts.append(ApprovalTimeText.relative(updatedAt))
        }
        return parts.joined(separator: " · ")
    }

    /// 成员行元信息：裁决口径与已决行同词（手动批
    /// 准／按规则放行／已驳回三分，照 decisionMeta）
    private func memberMeta(
        _ member: WriteGateActivityMember
    ) -> String {
        if member.state == "pending" {
            var text = L10n.string("待批")
            if let createdAt = member.createdAt {
                text += " · " + ApprovalTimeText.relative(createdAt)
            }
            return text
        }
        var head = member.decision == "approved"
            ? L10n.string("已批准") : L10n.string("已驳回")
        if member.viaRule != nil {
            head = L10n.string("已按规则放行")
        }
        guard let at = member.decidedAt ?? member.createdAt
        else { return head }
        return head + " · " + ApprovalTimeText.relative(at)
    }

    private func memberGlyphName(
        _ member: WriteGateActivityMember
    ) -> String {
        if member.state == "pending" { return "clock" }
        return member.decision == "approved" ? "checkmark" : "xmark"
    }

    private func memberGlyphTint(
        _ member: WriteGateActivityMember
    ) -> Color {
        if member.state == "pending" { return Palette.inkSecondary }
        return member.decision == "approved"
            ? Palette.success : Palette.danger
    }

    /// 组卡：一张卡一件活（头行与普通行同格），点按
    /// 展开组内每笔操作明细（只读——裁决仍只在聊天
    /// 面，本段口径不变）
    private func groupRow(_ group: WriteGateActivityGroup) -> some View {
        let entry = AuditEntry.activityGroup(group)
        let expanded = expandedGroupIDs.contains(group.id)
        return VStack(
            alignment: .leading,
            spacing: OneDayMetrics.spacingS
        ) {
            Button {
                if expanded {
                    expandedGroupIDs.remove(group.id)
                } else {
                    expandedGroupIDs.insert(group.id)
                }
            } label: {
                HStack(
                    alignment: .top,
                    spacing: OneDayMetrics.spacingSM
                ) {
                    rowGlyph(
                        systemImage: glyphName(for: entry),
                        tint: glyphTint(for: entry)
                    )
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingMicro
                    ) {
                        Text(title(for: entry))
                            .font(.system(
                                size: OneDayMetrics.hubTitleSize,
                                weight: .semibold
                            ))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(2)
                        if let description = description(for: entry) {
                            Text(description)
                                .font(.rowSubtitle)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(2)
                        }
                        Text(meta(for: entry))
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Image(
                        systemName: expanded
                            ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                expanded ? "收起这组记录" : "展开这组记录"
            )
            if expanded {
                ForEach(group.records) { member in
                    memberRow(member)
                }
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    /// 组内成员行：与已决行同三级排版、缩进一档（对
    /// 齐组头行文字缘），标题走已决同模板、副行走同
    /// 一 previewLine 口径
    private func memberRow(
        _ member: WriteGateActivityMember
    ) -> some View {
        HStack(
            alignment: .top,
            spacing: OneDayMetrics.spacingSM
        ) {
            rowGlyph(
                systemImage: memberGlyphName(member),
                tint: memberGlyphTint(member)
            )
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(member.headline)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                if let line = member.previewLine {
                    Text(line)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(2)
                }
                Text(memberMeta(member))
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: OneDayMetrics.spacingS)
        }
        .padding(.leading, OneDayMetrics.spacingSM + 24)
    }

    // MARK: - 审批规则（§493 迁入，与账本/记录同家）

    /// 审批规则入口：规则页本体 ApprovalRules-
    /// SettingsView（§244 曾归设置页，§493 改判迁
    /// 回本段直推）；页内含「总是允许」规则撤销、
    /// 命令授权与写入审批状态
    private var rulesSection: some View {
        Section {
            NavigationLink {
                ApprovalRulesSettingsView()
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    rowGlyph(
                        systemImage: "checkmark.shield",
                        tint: Palette.inkSecondary
                    )
                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("审批规则")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Text("「总是允许」规则、命令授权与写入审批")
                            .font(.subheadline)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(rowInsets)
                .padding(.vertical, OneDayMetrics.spacingXS)
            }
        } header: {
            Text("审批规则")
        }
    }

    // MARK: - 共用件

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Palette.inkSecondary)
            .listRowSeparator(.hidden)
            .listRowInsets(rowInsets)
            .padding(.vertical, OneDayMetrics.spacingXS)
    }

    /// 行左字形（§477）：无底盘、小字形（≈20）左置
    /// ——对参照审核帧形态，与工作行的 44 圆盘分工
    /// 勿混同（旧 40pt 圆角方盒退役；装饰字形隐藏
    /// 沿 wave1 无障碍口径）
    private func rowGlyph(
        systemImage: String, tint: Color
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(tint)
            .accessibilityHidden(true)
            .frame(width: 24, alignment: .center)
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: OneDayMetrics.hubGutter,
            bottom: 0,
            trailing: OneDayMetrics.hubGutter
        )
    }
}
