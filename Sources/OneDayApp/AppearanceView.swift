import OneDayDesign
import SwiftUI

/// 外观（0.2.1）：主题＝强调色五选一，本地持久化（AccentStore），
/// 全 App 染色点（按钮、选中态、链接、发送键、开关）即时生效。
/// 静态色（纸底、墨色、状态语义色）不随主题变。
struct AppearanceView: View {
    @State private var accent = AccentStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("主题")
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
                Text("只更换强调色：主按钮、选中态、链接、发送键与开关的颜色。背景、文字与状态色不变。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.top, OneDayMetrics.spacingM)
                SectionLabel("预览")
                    .padding(.top, 28)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: OneDayMetrics.spacingSM) {
                    HStack {
                        Spacer(minLength: 44)
                        Text("用户气泡用浅染，发送键用填充档")
                            .font(TypeScale.callout)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                Palette.primaryTint,
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.bubbleCorner)
                            )
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        Text("主按钮")
                            .font(TypeScale.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, OneDayMetrics.spacingM)
                            .frame(height: 40)
                            .background(
                                Palette.primaryFill,
                                in: RoundedRectangle(cornerRadius: OneDayMetrics.buttonCorner)
                            )
                        Text("链接与强调文字")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.primary)
                        Spacer()
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

    private func themeRow(_ theme: AccentTheme) -> some View {
        Button {
            accent.theme = theme
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                Circle()
                    .fill(Color(hex: theme.swatch))
                    .frame(width: 22, height: 22)
                    .frame(width: OneDayMetrics.iconSlot, alignment: .leading)
                    .accessibilityHidden(true)
                Text(theme.displayName)
                    .font(TypeScale.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: OneDayMetrics.spacingS)
                if accent.theme == theme {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
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
