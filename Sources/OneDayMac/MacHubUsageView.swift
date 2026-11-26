import SwiftUI
import OneDayCore

/// 用量面（棒 4，对位 #64）：近 30 天总量＋按日明
/// 细＋按模型明细（/api/analytics 系，与 iOS 用量
/// 面同口径：Token＝输入＋输出，缓存读不并入）
struct MacHubUsageView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            if let usage = store.usage {
                HubSectionHeader(title: "近 30 天总量")
                HubKVView(
                    label: "Token（入＋出）",
                    value: Self.formatTokens(usage.totals.tokens)
                )
                HubKVView(
                    label: "会话数",
                    value: "\(usage.totals.totalSessions ?? 0)"
                )
                HubKVView(
                    label: "API 调用",
                    value: "\(usage.totals.totalAPICalls ?? 0)"
                )
                if let cost = usage.totals.totalEstimatedCost {
                    HubKVView(
                        label: "估算费用",
                        value: String(format: "$%.2f", cost)
                    )
                }
                HubSectionHeader(
                    title: "按日", count: usage.daily.count
                )
                ForEach(usage.daily) { day in
                    HStack(spacing: 8) {
                        Text(day.day)
                            .font(.callout)
                            .frame(width: 90, alignment: .leading)
                        Text(Self.formatTokens(day.tokens))
                            .font(.callout)
                        Spacer()
                        Text("\(day.sessions ?? 0) 会话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "用量数据暂不可用。")
            }
            if let models = store.modelUsage {
                HubSectionHeader(
                    title: "按模型", count: models.models.count
                )
                ForEach(models.models) { model in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.model)
                                .font(.callout.weight(.medium))
                            Text(model.provider ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.formatTokens(model.tokens))
                            .font(.callout)
                    }
                    Divider()
                }
            }
        }
    }

    static func formatTokens(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return "\(Int(value))"
    }
}
