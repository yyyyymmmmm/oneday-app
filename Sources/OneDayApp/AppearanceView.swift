import OneDayDesign
import SwiftUI

/// 外观（0.2.1 立，0.3.7 卡 5 改版）：主题＝强调色五选一，
/// 本地持久化（AccentStore），全 App 染色点（按钮、选中
/// 态、链接、发送键、开关）即时生效。卡 5 口径：一控件
/// 一卡——顶部预览卡是真实聊天场景的实时渲染（助手泡/
/// 用户泡/发送舱/主按钮样例，文案是真实对话口吻，不许
/// 设计术语冒充消息），随所选主题即时变色；下方主题卡
/// 只做选择（色点＋名＋勾）。原假气泡组（写着「用户气
/// 泡用浅染，发送键用填充档」）与主题说明段已整组删
/// ——说明书文案不上屏，什么变什么不变在预览里看得见。
struct AppearanceView: View {
    @State private var accent = AccentStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("预览")
                    .padding(.bottom, OneDayMetrics.spacingS)
                previewCard
                SectionLabel("主题")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(Array(AccentTheme.allCases.enumerated()), id: \.element) { index, theme in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.dividerInset)
                        }
                        themeRow(theme)
                    }
                }
                .odGroup()
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        .navigationTitle("外观")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 真实聊天场景预览：气泡走真实令牌面（助手泡
    /// bubbleFill、用户泡中性面——§19 双气泡恒中性不
    /// 染色），发送舱走 fieldFill 胶囊＋primaryFill 发
    /// 送键，主按钮样例走 primaryFill 实填——主题切换
    /// 时只有强调位变色，与真实聊天页同口径。
    private var previewCard: some View {
        VStack(spacing: OneDayMetrics.spacingM) {
            HStack {
                Text("帮我把今天的安排整理一下")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Palette.surface,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                    )
                Spacer(minLength: 44)
            }
            HStack {
                Spacer(minLength: 44)
                Text("好的——上午十点和产品组对齐进度，下午三点前交周报初稿，其余时间没有安排。")
                    .font(TypeScale.callout)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Palette.bubbleFill,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                    )
            }
            HStack(spacing: OneDayMetrics.spacingS) {
                HStack {
                    Text("输入消息")
                        .font(TypeScale.callout)
                        .foregroundStyle(Palette.inkMuted)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(height: 40)
                .background(Palette.fieldFill, in: Capsule())
                ZStack {
                    Circle()
                        .fill(Palette.primaryFill)
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.onPrimary)
                        .accessibilityHidden(true)
                }
            }
            HStack {
                Text("主按钮")
                    .font(TypeScale.headline)
                    .foregroundStyle(Palette.onPrimary)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(height: 40)
                    .background(
                        Palette.primaryFill,
                        in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
                    )
                Spacer()
            }
        }
        .padding(OneDayMetrics.spacingM)
        .odGroup()
    }

    private func themeRow(_ theme: AccentTheme) -> some View {
        Button {
            accent.theme = theme
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Circle()
                    .fill(theme.swatchColor)
                    .frame(width: 22, height: 22)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(theme.displayName)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                if accent.theme == theme {
                    Image(systemName: "checkmark")
                        // 卡 17：勾字形 regular
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Palette.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.displayName)
    }
}
