import OneDayCore
import OneDayDesign
import SwiftUI

/// 留痕回响卡（P0 App 侧呈现，2026-11-13；P2 首链
/// 「自开旁聊」）：AI 内部动作做完（或做砸）后在对话
/// 流里的交代卡——五要素齐备：动作名（卡头短句）／
/// 对象（目标标题行，会话类可点达）／时间（右上）／
/// 结果（成功原样）／失败（原文整行、红边红字、与
/// 成功同级不折叠）。几何与回告卡同族（surface 底＋
/// hairline 边＋containerCorner），失败态换 danger 边。
///
/// 本件是公用件：其余动作（目标/身份/自动化/触达各包）
/// 的回响共用同一卡面，文案口径在 Core TraceEchoCopy、
/// 呈现范围在 Core TraceEchoPolicy，本件只管长相与
/// 点达出口，不自带数据与判定。
struct TraceEchoCard: View {
    let trace: BridgeTrace
    /// 智能体显示名（卡头主语，跟随服务器命名链，
    /// 由宿主传入——本件不读全局状态）
    let agentName: String
    /// 点达出口（会话类目标）：宿主走既有续聊通道
    /// （pendingChatSessionID 置位→导入/切换），本件
    /// 只报 id、不自导航
    var onOpenSession: (String) -> Void = { _ in }

    private var openableSessionID: String? {
        TraceEchoCopy.openableSessionID(trace)
    }

    var body: some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(
                    trace.isFailed ? Palette.danger
                        : Palette.inkSecondary
                )
                .accessibilityHidden(true)
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(TraceEchoCopy.headline(
                    trace: trace, agentName: agentName
                ))
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                if !trace.target.label.isEmpty {
                    HStack(spacing: OneDayMetrics.spacingMicro) {
                        Text(trace.target.label)
                            .font(.footnote)
                            .foregroundStyle(
                                openableSessionID != nil
                                    ? Palette.primary
                                    : Palette.inkSecondary
                            )
                            .lineLimit(1)
                        if openableSessionID != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.primary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                let outcome = TraceEchoCopy.outcomeLine(trace)
                if !outcome.isEmpty {
                    Text(outcome)
                        .font(.footnote)
                        .foregroundStyle(
                            trace.isFailed ? Palette.danger
                                : Palette.inkSecondary
                        )
                        .lineLimit(trace.isFailed ? 4 : 3)
                }
            }
            Spacer(minLength: 0)
            Text(timeText)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .accessibilityLabel(timeText)
        }
        .padding(OneDayMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
            .strokeBorder(
                trace.isFailed ? Palette.danger : Palette.hairline,
                lineWidth: 1
            )
        }
        .contentShape(Rectangle())
        // 点达：整卡可点（与回告卡同手法），仅会话类
        // 目标接出口；点不达的卡无手势、不装可点
        .onTapGesture {
            if let openableSessionID {
                onOpenSession(openableSessionID)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 时间要素：今天只给时刻、跨日带月日（原生格式，
    /// 随系统 locale——卡面其余文案为产品中文，时间
    /// 走系统口径与全 App 时间呈现一致）
    private var timeText: String {
        if Calendar.current.isDateInToday(trace.date) {
            return trace.date.formatted(
                .dateTime.hour().minute())
        }
        return trace.date.formatted(
            .dateTime.month().day().hour().minute())
    }
}
