import OneDayCore
import OneDayDesign
import SwiftUI

/// 通知权限段（引导段模板的呈现面，蓝本＝nanoMuse
/// 通知页：用途先行、两条具体用途、主按钮随状态
/// 变、可跳过、细字给退路）。纯呈现＋回调注入：状
/// 态由宿主持有、动作经回调出去——段内文案与状态→
/// 动作判定全走 Core 的 NotificationGuideSegment 模
/// 板，本面不自拟话术、不自立状态机。后续权限申请
/// 面复用本面时，换宿主接线即可。
///
/// 状态语义（与模板同口径）：
/// - 未决定：主按钮「允许通知」发那一次请求，下方
///   「暂时跳过」；
/// - 已授权（请求落定或进面时已授权）：确认行＋主
///   按钮变前进词（宿主给的 advanceTitle）；
/// - 已拒绝：主按钮「去系统设置开启」，跳过仍在，
///   不纠缠。
struct NotificationGuideView: View {
    /// 当前真状态（宿主现读后注入；段内请求/设置往
    /// 返后由宿主刷新重注入）
    let state: DevicePermissionState
    /// 前进词：本段是宿主流程终点时由宿主命名（如
    /// 连接页给「开始聊天」），缺省用模板缺省词
    var advanceTitle: String = NotificationGuideSegment
        .primaryButtonTitle(for: .continueNext)
    /// 发那一次系统请求（仅未决定态可达）
    var onRequest: () -> Void
    /// 去系统设置开启（仅已拒绝态可达）
    var onOpenSettings: () -> Void
    /// 前进/跳过（离开本段，进宿主流程的下一步）
    var onAdvance: () -> Void

    private var action: PermissionSegmentAction {
        NotificationGuideSegment.action(for: state)
    }

    /// 确认行只在真授权时出现（引擎侧 translate 只
    /// 产 granted/denied/notDetermined 三档）
    private var isEnabled: Bool {
        state == .granted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "bell")
                .font(.system(size: 28))
                .foregroundStyle(Palette.primary)
                .frame(width: 70, height: 70)
                .background(
                    Palette.primaryPale,
                    in: RoundedRectangle(
                        cornerRadius: OneDayMetrics.containerCorner,
                        style: .continuous
                    )
                )
                .padding(.bottom, OneDayMetrics.spacingXL)
                .accessibilityHidden(true)
            Text(NotificationGuideSegment.title())
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(NotificationGuideSegment.intro())
                .font(.callout)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingS)

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
                ForEach(
                    Array(NotificationGuideSegment.useCases().enumerated()),
                    id: \.offset
                ) { _, use in
                    HStack(alignment: .top, spacing: OneDayMetrics.spacingM) {
                        Image(systemName: use.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.primary)
                        VStack(
                            alignment: .leading,
                            spacing: OneDayMetrics.spacingMicro
                        ) {
                            Text(use.title)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Palette.ink)
                            Text(use.detail)
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            }
            .padding(.top, OneDayMetrics.spacingXL)

            if isEnabled {
                HStack(spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.success)
                    Text(NotificationGuideSegment.enabledNote())
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Palette.ink)
                }
                .padding(.top, OneDayMetrics.spacingL)
            }

            // 标题均为 Core 模板已本地化的 String，
            // 走 label＋Text 直出，不再当 Key 二次查表
            Button {
                switch action {
                case .requestOnce: onRequest()
                case .continueNext: onAdvance()
                case .openSettings: onOpenSettings()
                }
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(.odPrimary)
            .padding(.top, OneDayMetrics.spacingXL)

            if action != .continueNext {
                Button {
                    onAdvance()
                } label: {
                    Text(NotificationGuideSegment.skipTitle())
                }
                .font(.callout)
                .foregroundStyle(Palette.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OneDayMetrics.minTapTarget)
            }

            Text(NotificationGuideSegment.finePrint())
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, OneDayMetrics.spacingM)
        }
    }

    private var primaryTitle: String {
        action == .continueNext
            ? advanceTitle
            : NotificationGuideSegment.primaryButtonTitle(for: action)
    }
}
