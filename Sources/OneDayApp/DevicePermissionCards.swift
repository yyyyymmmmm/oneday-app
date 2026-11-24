import OneDayCore
import OneDayDesign
import SwiftUI

/// 对话内授权卡（DESIGN §244，规格 permission-system-
/// redesign-20261113 §7.3/§7.5）：智能体的调用卡在权
/// 限上时，卡直接长在当前对话流里——讲清这次要哪件、
/// 数据去哪，用户点「允许」才烧那一次系统窗；已拒绝
/// 的给「去设置打开」，回来自动续办，不让人重述一遍。
///
/// 呈现层拼装、不写消息（与 §165 审批卡同先例）：设
/// 备通道没有 Hermes 会话归属字段，卡汇当前对话流末
/// 尾；状态与动作全在 DevicePermissionCoordinator。
struct ChatPermissionZone: View {
    @Environment(AppState.self) private var appState

    private var flow: DevicePermissionCoordinator {
        appState.deviceSession.permissionFlow
    }

    var body: some View {
        if flow.hasVisibleCards {
            VStack(spacing: OneDayMetrics.spacingM) {
                ForEach(flow.cards) { card in
                    PermissionCardView(card: card)
                }
            }
        }
    }
}

private struct PermissionCardView: View {
    let card: PermissionCard

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    private var host: DeviceSessionController { appState.deviceSession }
    private var flow: DevicePermissionCoordinator { host.permissionFlow }
    private var descriptor: DeviceSourceDescriptor {
        DeviceSourceDirectory.descriptor(card.source)
    }

    var body: some View {
        switch card.phase {
        case .done, .declined, .expired:
            settledLine
        default:
            activeCard
        }
    }

    // MARK: - 终态痕迹行（与审批卡已决行同形态）

    private var settledLine: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: settledIcon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(settledColor)
            Text(settledText)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
            Spacer()
            Button("收起") { flow.dismiss(cardID: card.id) }
                .font(.footnote)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingS)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
        )
    }

    private var settledIcon: String {
        switch card.phase {
        case .done: return "checkmark.circle.fill"
        case .declined: return "minus.circle.fill"
        default: return "clock.badge.exclamationmark"
        }
    }

    private var settledColor: Color {
        switch card.phase {
        case .done: return Palette.success
        case .declined: return Palette.inkMuted
        default: return Palette.warning
        }
    }

    private var settledText: String {
        switch card.phase {
        case .done:
            return "「\(descriptor.name)」\(card.resultSummary ?? "已办完。")"
        case .declined:
            return "用到「\(descriptor.name)」的那件事先算了。"
        default:
            return "那次「\(descriptor.name)」的授权等太久，已经作废了。"
        }
    }

    // MARK: - 活卡

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
            HStack(spacing: OneDayMetrics.spacingS) {
                Image(systemName: descriptor.tileSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.primary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text(bodyText)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(OneDayMetrics.spacingM)
        .background(
            Palette.surface,
            in: RoundedRectangle(
                cornerRadius: OneDayMetrics.containerCorner
            )
        )
    }

    private var title: String {
        switch card.phase {
        case .primer: return "要用到你的「\(descriptor.name)」"
        case .asking: return "等你确认"
        case .blocked: return "「\(descriptor.name)」还没打开"
        case .parked: return "这件先放着了"
        case .switchOff: return "差一步：调用开关没开"
        case .resuming: return "正在接着办"
        case .failed: return "刚才没办成"
        default: return descriptor.name
        }
    }

    private var bodyText: String {
        let action = DeviceToolRegistry.spec(card.tool)?.isWrite == true
            ? "办一件事" : "查一下"
        switch card.phase {
        case .primer:
            var text = "智能体刚才想用「\(descriptor.name)」\(action)，需要你先允许。数据只发到你自己的服务器，不给第三方。"
            if card.isSyncQuery {
                text += "允许后会先把「\(descriptor.name)」同步过去再查。"
            }
            if card.source == .motion {
                // G10 诚实口径：计步授权在系统侧必然
                // 伴随一次今日步数查询，如实先说
                text += "允许的同时系统会顺带查一次今天的步数，这是系统定的，问完就好。"
            }
            return text
        case .asking:
            return "在系统弹窗里点「允许」就行；不想给就点「不允许」，不会反复弹。"
        case .blocked:
            return "之前在系统里没允许「\(descriptor.name)」。去设置里打开它，回来会自动接着办刚才的事，不用重新说一遍。"
        case .parked:
            // §261 ③：桥记了「未答」的与用户主动「先
            // 不」分开说——不是他拒绝了，是当时没顾上
            if card.askUnanswered {
                return "刚才问的时候没等到你答复，那件事先放着了。点「继续」接着来，不用重新跟智能体说。"
            }
            return "用到「\(descriptor.name)」的那件事还没办。点「继续」接着来，不用重新跟智能体说。"
        case .switchOff:
            return "「\(descriptor.name)」的系统权限已经有了，只是「允许智能体调用」还关着。打开后马上接着办刚才的事。"
        case .resuming:
            return "正在把刚才那件事接着办完。"
        case .failed:
            return card.failureNote ?? "点「再试一次」再试试。"
        default:
            return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch card.phase {
        case .primer:
            HStack(spacing: OneDayMetrics.spacingS) {
                Button("先不") { flow.park(cardID: card.id) }
                    .buttonStyle(.bordered)
                Button("允许") {
                    Task { await flow.allow(cardID: card.id, host: host) }
                }
                .buttonStyle(.borderedProminent)
            }
        case .asking, .resuming:
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text(card.phase == .asking ? "等你确认…" : "正在办…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .blocked:
            HStack(spacing: OneDayMetrics.spacingS) {
                Button("算了") { flow.decline(cardID: card.id) }
                    .buttonStyle(.bordered)
                Button("去设置打开") {
                    if let url = URL(
                        string: UIApplication.openSettingsURLString
                    ) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .parked:
            HStack(spacing: OneDayMetrics.spacingS) {
                Button("算了") { flow.decline(cardID: card.id) }
                    .buttonStyle(.bordered)
                Button("继续") { flow.reopen(cardID: card.id) }
                    .buttonStyle(.borderedProminent)
            }
        case .switchOff:
            HStack(spacing: OneDayMetrics.spacingS) {
                Button("算了") { flow.decline(cardID: card.id) }
                    .buttonStyle(.bordered)
                Button("打开并继续") {
                    Task {
                        await flow.enableSwitchAndResume(
                            cardID: card.id, host: host
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed:
            HStack(spacing: OneDayMetrics.spacingS) {
                Button("算了") { flow.decline(cardID: card.id) }
                    .buttonStyle(.bordered)
                Button("再试一次") {
                    Task { await flow.resume(cardID: card.id, host: host) }
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            EmptyView()
        }
    }
}
