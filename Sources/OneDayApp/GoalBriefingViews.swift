import OneDayCore
import OneDayDesign
import SwiftData
import SwiftUI

/// A-11 结构拆分（2026-11-16）：自 GoalsView.swift 按职责拆出（状态 chip 与简报两页），内容逐字未改、零行为变更（DESIGN §311）。

/// 状态 chip：进行中＝绿点＋绿字浅底；已完成＝灰字，
/// 带完成时刻（桥落字的 completedAt，相对时间口径）
struct GoalStatusChip: View {
    let goal: BridgeGoal

    var body: some View {
        HStack(spacing: OneDayMetrics.iconTextGap) {
            Circle()
                .fill(
                    goal.status == .completed
                        ? Palette.inkMuted : Palette.success
                )
                .frame(width: 6.5, height: 6.5)
            Text(label)
                // 0.41.0（P6）：chip 字回收 footnote
                // regular，状态靠色与点、不靠字重
                .font(.footnote)
                .foregroundStyle(
                    goal.status == .completed
                        ? Palette.inkSecondary : Palette.successText
                )
        }
        .padding(.horizontal, OneDayMetrics.spacingS)
        .padding(.vertical, OneDayMetrics.spacingXS)
        .background(
            goal.status == .completed ? Palette.surface : Palette.tintGreen,
            in: Capsule()
        )
    }

    private var label: String {
        switch goal.status {
        case .active:
            return "进行中"
        case .completed:
            if let completedAt = goal.completedAt {
                let when = ChatTimeline.dividerText(
                    for: Date(timeIntervalSince1970: completedAt),
                    now: Date()
                )
                return "已完成 · \(when)"
            }
            return "已完成"
        }
    }
}

/// 简报列表页（GD-3）：一行一封信——标题＋首句摘要
/// （≤40 字）＋日期，不在列表铺全文；点行进信件页
/// 读全文。只读——简报正文不许在客户端改（设计档
/// 状态机口径，纠错靠新条目）
struct GoalBriefingsView: View {
    let store: GoalsStore
    let goalID: String

    private var briefings: [BridgeBriefing] {
        store.briefingsByGoal[goalID] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if briefings.isEmpty {
                    Text("还没有简报。")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
                ForEach(
                    Array(briefings.enumerated()), id: \.element.id
                ) { index, briefing in
                    if index > 0 {
                        GroupDivider()
                    }
                    NavigationLink {
                        GoalBriefingLetterView(
                            store: store, goalID: goalID,
                            briefingID: briefing.id
                        )
                    } label: {
                        HStack(
                            spacing: OneDayMetrics.spacingSM
                        ) {
                            VStack(
                                alignment: .leading, spacing: 3
                            ) {
                                Text(briefing.title)
                                    .font(.rowTitle)
                                    .foregroundStyle(Palette.bodyInk)
                                    .multilineTextAlignment(.leading)
                                Text(
                                    BriefingPresentation.summary(
                                        of: briefing.body
                                    )
                                )
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                Text(
                                    "\(ChatTimeline.dividerText(for: Date(timeIntervalSince1970: briefing.createdAt), now: Date())) · \(briefing.period)"
                                )
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            DisclosureChevron(font: .footnote.weight(.semibold))
                        }
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("简报")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 简报信件页（GD-3 信纸排版）：一封信一页——信纸
/// 面（与页面底色区分的纸面）＋称呼行（目标名＋第
/// N 周）＋信体分段（纯文本段落，不进表格/列表渲
/// 染）＋信尾短注＋落款行（日期＋「OneDay 目标简
/// 报」）。打开即把打开时刻记到桥上——只供台账看
/// 「写了没看」，本页不呈现任何已读/未读标记
struct GoalBriefingLetterView: View {
    @Environment(AppState.self) private var appState

    let store: GoalsStore
    let goalID: String
    let briefingID: String

    private var briefing: BridgeBriefing? {
        store.briefingsByGoal[goalID]?.first { $0.id == briefingID }
    }

    private var week: Int? {
        BriefingPresentation.weekIndex(
            of: briefingID, in: store.briefingsByGoal[goalID] ?? []
        )
    }

    var body: some View {
        ScrollView {
            if let briefing {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingM
                ) {
                    // 称呼行：写给哪个目标的第几封信
                    HStack(spacing: OneDayMetrics.spacingS) {
                        if let goal = store.goal(id: goalID) {
                            Text("《\(goal.title)》")
                                .font(.body.weight(.medium))
                                .foregroundStyle(Palette.bodyInk)
                        }
                        if let week {
                            Text(L10n.format("第 %lld 周", week))
                                .font(.body)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    Text(briefing.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.bodyInk)
                    // 信体：按段落分段的纯文本
                    VStack(
                        alignment: .leading,
                        spacing: OneDayMetrics.spacingSM
                    ) {
                        ForEach(
                            Array(
                                briefing.body
                                    .components(separatedBy: "\n\n")
                                    .enumerated()
                            ),
                            id: \.offset
                        ) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(Palette.bodyInk)
                        }
                    }
                    // 信尾短注：这封信依据了哪些真实
                    // 变化（桥按计数拼装，安静一行）
                    if let note = briefing.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    // 落款行
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Text(
                            ChatTimeline.dividerText(
                                for: Date(
                                    timeIntervalSince1970:
                                        briefing.createdAt
                                ),
                                now: Date()
                            )
                        )
                        Text("OneDay 目标简报")
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                }
                .padding(OneDayMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.containerCorner,
                        style: .continuous
                    )
                )
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.vertical, OneDayMetrics.spacingM)
            } else {
                Text("这封信已经不在了。")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(OneDayMetrics.pageGutter)
            }
        }
        .background(Palette.pageBG)
        .navigationTitle("简报")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.markBriefingOpened(
                appState: appState, goalID: goalID,
                briefingID: briefingID
            )
        }
    }
}

