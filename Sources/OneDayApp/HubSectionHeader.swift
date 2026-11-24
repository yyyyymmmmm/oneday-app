import OneDayDesign
import SwiftUI

/// §477 中枢段头单源件（2026-11-24 全抄参照）：工
/// 作/审核两页段头同一形态——17 semibold 主黑
/// （§500 订正：§477 的 ≈20 系误记，量测实测
/// ≈17，hub-type-measurement-20261124.md）、
/// 白底无系统灰底带（不用 List 系统 Section 头，形
/// 态与边距全由本件控制，作段内首行呈现）。可折叠
/// 时带 chevron（展开指上、收起指下，对参照帧）并
/// 整行可点（工作页两段用）；静态段头（审核页）无
/// chevron、不可点。横边距由消费方行 insets 承接
/// （hubGutter），本件只管字与形。
struct HubSectionHeader: View {
    let title: String
    /// nil ＝ 静态段头；非 nil ＝ 可折叠，值＝当前展开态
    var isExpanded: Bool? = nil
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: OneDayMetrics.iconTextGap) {
            Text(title)
                .font(.system(
                    size: OneDayMetrics.hubTitleSize,
                    weight: .semibold
                ))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let isExpanded {
                Image(
                    systemName: isExpanded
                        ? "chevron.up" : "chevron.down"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OneDayMetrics.spacingS)
        .contentShape(Rectangle())
        .onTapGesture { onToggle?() }
        .accessibilityAddTraits(onToggle == nil ? [] : .isButton)
    }
}
