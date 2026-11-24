import ActivityKit
import OneDayCore
import SwiftUI
import WidgetKit

/// OneDay 扩展入口（总表 163，DESIGN §385.3）：本
/// 扩展只承载实时活动呈现面（锁屏＋灵动岛），不放
/// 桌面小组件。呈现只消费 RunLiveActivityAttributes
/// 的任务名与阶段——属性型本身不带正文字段，锁屏
/// 可见面无正文可呈（隐私口径在型上钉死）。
@main
struct OneDayWidgets: WidgetBundle {
    var body: some Widget {
        RunLiveActivityWidget()
    }
}

struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: RunLiveActivityAttributes.self
        ) { context in
            // 锁屏面：图标＋任务名＋阶段＋阶段计时
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.taskName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.phase.label())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(
                    context.state.phaseStartedAt,
                    style: .timer
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(
                Color.black.opacity(0.35)
            )
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase.label())
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.taskName)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text(context.state.phase.label())
                    .font(.caption2)
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}
