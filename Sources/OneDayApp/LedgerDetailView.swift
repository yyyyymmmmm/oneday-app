import OneDayCore
import OneDayDesign
import SwiftUI

/// 台账条目详情（下钻）：事件时间线全流水＋失败证
/// 据＋子计数；原始枚举只许出现在本页「技术信息」
/// 区（宪法口径：列表面零行话，排障原文有唯一的
/// 家）。进页拉详情面（列表快照先顶着渲染，history
/// 只在详情面有），记录已不在如实露。
struct LedgerDetailView: View {
    var store: LedgerStore
    /// 列表快照行（详情回执到达前先以它渲染）
    let item: LedgerItem
    var onOpenSession: (String) -> Void

    @Environment(AppState.self) private var appState

    /// 详情回执（id 对得上才用）优先，缺失回落列表快照
    private var current: LedgerItem {
        if let detail = store.detail, detail.id == item.id {
            return detail
        }
        return item
    }

    private var sessionTarget: String? {
        if let link = current.link, link.kind == "session",
           !link.targetId.isEmpty {
            return link.targetId
        }
        return current.sessionId
    }

    var body: some View {
        List {
            headerSection
            overviewSection
            if current.toolCalls != nil || current.subTasks != nil {
                countsSection
            }
            if let reason = current.failReason {
                failSection(reason)
            }
            if let target = sessionTarget {
                Section {
                    Button {
                        onOpenSession(target)
                    } label: {
                        Label("打开会话", systemImage: "bubble.left")
                    }
                }
            }
            historySection
            technicalSection
        }
        .listStyle(.plain)
        .navigationTitle("工作详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadDetail(appState: appState, id: item.id)
        }
    }

    // MARK: - 段

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(
                    "\(LedgerText.statusWord(current.status)) · \(LedgerText.sourceWord(current.source))"
                )
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
                if current.isReconciled {
                    Text("这条是对账时补记的：它开始时台账还没记上。")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .padding(.vertical, OneDayMetrics.spacingMicro)
            .listRowSeparator(.hidden)
        }
    }

    private var overviewSection: some View {
        Section("概况") {
            row("类别", LedgerText.kindWord(current.kind))
            row("来源", LedgerText.sourceWord(current.source))
            row(
                "开始",
                DisplayDate.dateTime(
                    Date(timeIntervalSince1970: current.startedAt)
                )
            )
            if let ended = current.endedAt {
                row(
                    "结束",
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: ended)
                    )
                )
            }
            if let evidence = current.lastEvidenceAt {
                row(
                    "最后确认",
                    DisplayDate.dateTime(
                        Date(timeIntervalSince1970: evidence)
                    )
                )
            }
            if current.status.isActive {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let text = LedgerBoard.durationText(
                        for: current,
                        serverNow: store.displayServerNow(
                            at: context.date
                        )
                    ) {
                        row("已耗时", text)
                    }
                }
            } else if let text = LedgerBoard.durationText(
                for: current, serverNow: store.serverNow
            ) {
                row("用时", text)
            }
        }
    }

    private var countsSection: some View {
        Section("工作量") {
            if let calls = current.toolCalls {
                row("工具调用", "\(calls) 次")
            }
            if let subs = current.subTasks {
                row("子任务", "\(subs) 个")
            }
        }
    }

    private func failSection(
        _ reason: LedgerFailReason
    ) -> some View {
        Section("原因") {
            row("分类", reason.category)
            if let excerpt = reason.excerpt, !excerpt.isEmpty {
                Text(excerpt)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("事件时间线") {
            if store.detailGone {
                Text("这条记录已不在，时间线读不到。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            } else if store.detail?.id == item.id {
                if current.history.isEmpty {
                    Text("暂无流转记录。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    ForEach(
                        Array(current.history.enumerated()),
                        id: \.offset
                    ) { _, entry in
                        historyRow(entry)
                    }
                }
            } else if store.detailLoading {
                HStack(spacing: OneDayMetrics.spacingS) {
                    ProgressView().controlSize(.small)
                    Text("正在读取时间线…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else {
                Text("时间线暂时读不到。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func historyRow(_ entry: LedgerHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(
                    LedgerClock.timeWithSeconds(entry.at)
                )
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Palette.inkMuted)
                Text(transitionText(entry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(LedgerText.actorWord(entry.by))
                    .font(.footnote)
                    .foregroundStyle(Palette.inkMuted)
            }
            if entry.corrected {
                tag("对账纠正")
            } else if entry.conflict {
                tag("证据有冲突 · 保持原判")
            }
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.vertical, 1)
    }

    private func transitionText(_ entry: LedgerHistoryEntry) -> String {
        let to = LedgerText.statusWord(
            LedgerStatus(rawValue: entry.to)
        )
        guard let from = entry.from else { return "开始 · \(to)" }
        return "\(LedgerText.statusWord(LedgerStatus(rawValue: from))) → \(to)"
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.inkMuted)
    }

    /// 技术信息：原始枚举与编号只进本区（排障用），
    /// 列表面不露
    private var technicalSection: some View {
        Section("技术信息") {
            row("状态原文", current.status.rawValue)
            row("类别原文", current.kind.rawValue)
            row("来源原文", current.source.rawValue)
            row("记账来源", LedgerText.originWord(current.origin))
            row("标题来源", LedgerText.titleSourceWord(current.titleSource))
            row("条目编号", current.id)
            if let session = current.sessionId {
                row("会话编号", session)
            }
            if let run = current.runId {
                row("运行编号", run)
            }
            if let by = current.correctedBy {
                row("纠正者", by)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
