import OneDayCore
import OneDayDesign
import SwiftUI

/// 定时任务只读行（台账 198 收敛·行件合一）：枢纽
/// 定时段与状态页定时摘录共用同一行件——此前两面
/// 各绘一份（枢纽自绘带方片/圆盘、状态页自绘纯文
/// 字行），数据合一（CronStore）后呈现也只许一种。
/// 行型：提醒/每日用日历方片＋琥珀角标（L5），间隔
/// 用时钟圆盘；文案口径（数据设计 §3.4）：时间一
/// 律走 nextRunAt 绝对时刻，取不到回落 scheduleText，
/// 不编造。本体自 HubCronSection 原行抽出、逐值不变。
/// §344（中枢四欠账·记录行三段式）：行改三段——左
/// 方片/圆盘／中题＋计划说明／右段时间列；时间文
/// 本自中列移入右列（.metaMonospaced 等宽次色，与
/// 公用行件 ContentRow 右段同角色），中列只留计
/// 划说明、无下次时刻时回落 scheduleText 的旧兜
/// 底不变。本行件两面共用、同步同改（行件合一）
struct CronOverviewRow: View {
    let item: HubCronItem

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            switch item.kind {
            case .reminder, .daily, .otherRecurring:
                calendarTile(withBadge: item.kind != .otherRecurring)
            case .interval:
                clockDisc
            }
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                HStack(spacing: OneDayMetrics.rowInnerGap) {
                    Text(item.job.title)
                        .font(.body)
                        .foregroundStyle(
                            item.job.enabled ? Palette.ink : Palette.inkSecondary
                        )
                        .lineLimit(1)
                    if !item.job.enabled {
                        Text("已暂停")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                ForEach(planLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if !timeLines.isEmpty {
                VStack(
                    alignment: .trailing,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    ForEach(timeLines, id: \.self) { line in
                        Text(line)
                            .font(.metaMonospaced)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    /// 中列计划说明（数据设计 §3.4；§344 起时间不
    /// 进中列）：提醒/每日有下次时刻时中列不出文
    /// 本（时刻在右列），取不到回落 scheduleText；
    /// 间隔行给间隔说明；其他周期给计划说明
    private var planLines: [String] {
        switch item.kind {
        case .reminder, .daily:
            return item.nextRunAt == nil
                ? [item.job.scheduleText] : []
        case .interval:
            if let intervalText = item.intervalText {
                return [intervalText]
            }
            return [item.job.scheduleText]
        case .otherRecurring:
            return [item.job.scheduleText]
        }
    }

    /// 右段时间列（§344）：提醒＝下次「M月d日」＋
    /// 「HH:mm」两行；每日＝下次「HH:mm」；间隔＝
    /// 上次运行相对时刻；其他周期＝下次 short 时刻。
    /// 取不到时刻返回空列（不编造，与 §3.4 同口径）
    private var timeLines: [String] {
        switch item.kind {
        case .reminder:
            guard let next = item.nextRunAt else { return [] }
            return [
                AdminFormat.day(next),
                AdminFormat.timeOnly(next),
            ]
        case .daily:
            guard let next = item.nextRunAt else { return [] }
            return [AdminFormat.timeOnly(next)]
        case .interval:
            guard let last = item.lastRunAt else { return [] }
            return ["上次运行 \(last.formatted(.relative(presentation: .named)))"]
        case .otherRecurring:
            guard let next = item.nextRunAt else { return [] }
            return [AdminFormat.short(next)]
        }
    }

    /// 日历方片＋右下琥珀时钟角标（L5，用户定案④打
    /// 包；角标色 #E6B036 依基线补遗，暗色给同系深值）
    private func calendarTile(withBadge: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb)
                    .fill(Palette.surface)
                RoundedRectangle(cornerRadius: OneDayMetrics.radiusThumb)
                    .stroke(Palette.hairline, lineWidth: 0.5)
                Image(systemName: "calendar")
                    .font(.system(size: FrameworkIcon.tabGlyphSize))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 44, height: 44)

            if withBadge {
                // 0.36.0（无障碍 A11Y-D2 部分）：角标
                // 字形原 8pt 过小——徽标 16→18、字形
                // 8→10 放大一档（图形角标非文字，放大
                // 后仍属装饰级尺寸，已在台账注明）
                ZStack {
                    Circle().fill(Self.amber)
                    Image(systemName: "clock.fill")
                        .font(.system(size: FrameworkIcon.badgeGlyphSize, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
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
                .font(.system(size: FrameworkIcon.tabGlyphSize))
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
