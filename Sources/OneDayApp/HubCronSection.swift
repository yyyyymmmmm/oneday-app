import OneDayCore
import OneDayDesign
import SwiftUI

/// 枢纽页定时段（规格 §3.4）：只读概览——提醒/每日/
/// 时间间隔（＋其他周期兜底组），点行跳 CronJobsView
/// 管理；本段不放新建/删除/启停。行型：提醒/每日用
/// 日历方片＋琥珀角标（L5），间隔用时钟圆盘。
struct HubCronSection: View {
    let store: AgentHubStore

    var body: some View {
        if store.cronFailed {
            ContentUnavailableView {
                Label("定时任务读取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text("请稍后重试。")
            } actions: {
                Button("重试") {
                    Task { await store.loadCronIfNeeded() }
                }
                .buttonStyle(.bordered)
            }
        } else if let groups = store.cronGroups {
            if groups.isEmpty {
                ContentUnavailableView(
                    "暂无定时任务",
                    systemImage: "clock",
                    description: Text("还没有建过定时任务")
                )
            } else {
                List {
                    ForEach(groups, id: \.kind) { group in
                        Section(group.kind.groupTitle) {
                            ForEach(group.items) { item in
                                NavigationLink {
                                    CronJobsView()
                                } label: {
                                    row(item)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func row(_ item: HubCronItem) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            switch item.kind {
            case .reminder, .daily, .otherRecurring:
                calendarTile(withBadge: item.kind != .otherRecurring)
            case .interval:
                clockDisc
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.job.title)
                        .font(.body)
                        .foregroundStyle(
                            item.job.enabled ? Palette.ink : Palette.inkSecondary
                        )
                        .lineLimit(1)
                    if !item.job.enabled {
                        Text("已暂停")
                            .font(.caption)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                ForEach(textLines(item), id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// 行文案（数据设计 §3.4）：时间一律走 nextRunAt
    /// 绝对时刻；取不到时刻时回落 scheduleText，不编造
    private func textLines(_ item: HubCronItem) -> [String] {
        switch item.kind {
        case .reminder:
            guard let next = item.nextRunAt else {
                return [item.job.scheduleText]
            }
            return [
                AdminFormat.day(next),
                AdminFormat.timeOnly(next),
            ]
        case .daily:
            guard let next = item.nextRunAt else {
                return [item.job.scheduleText]
            }
            return [AdminFormat.timeOnly(next)]
        case .interval:
            var lines: [String] = []
            if let intervalText = item.intervalText {
                lines.append(intervalText)
            } else {
                lines.append(item.job.scheduleText)
            }
            if let last = item.lastRunAt {
                lines.append("上次运行 \(last.formatted(.relative(presentation: .named)))")
            }
            return lines
        case .otherRecurring:
            var lines = [item.job.scheduleText]
            if let next = item.nextRunAt {
                lines.append(AdminFormat.short(next))
            }
            return lines
        }
    }

    /// 日历方片＋右下琥珀时钟角标（L5，用户定案④打包；
    /// 角标色 #E6B036 依基线补遗，暗色给同系深值）
    private func calendarTile(withBadge: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.surface)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44, height: 44)

            if withBadge {
                ZStack {
                    Circle().fill(Self.amber)
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
                .offset(x: 4, y: 4)
            }
        }
        .frame(width: 48, height: 48)
    }

    /// 间隔行时钟圆盘（规格 #34：细线表盘拼装）
    private var clockDisc: some View {
        ZStack {
            Circle().stroke(Palette.hairline, lineWidth: 1)
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: 44, height: 44)
        .frame(width: 48, height: 48)
    }

    private static let amber = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xC9 / 255.0, green: 0x96 / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : UIColor(red: 0xE6 / 255.0, green: 0xB0 / 255.0, blue: 0x36 / 255.0, alpha: 1)
    })
}
