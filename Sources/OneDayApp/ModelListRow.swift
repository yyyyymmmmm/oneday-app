import OneDayDesign
import SwiftUI

/// 模型行单件（台账 199，普查 R3 收敛）：全 App 模
/// 型列表的行渲染只留这一套——顶栏选择面（本会话
/// 作用域，ChatModelPickerView）与设置侧治理清单／
/// 默认选择面（服务端默认作用域，GovernedModel-
/// Rows）共用。作用域与落账路径留在各自宿主（数
/// 据层），行件只管呈现：名＋副行＋当前勾＋当前
/// 附加标。onSelect 为 nil 时是静态行（设置侧
/// 「已是默认」行不可再点的口径）；名体两式（正
/// 文／等宽）由宿主按面给——设置侧模型 id 用等宽
/// 对齐可辨，顶栏面用正文字
struct ModelListRow: View {
    let title: String
    var subline: String? = nil
    var isCurrent: Bool = false
    /// 当前行附加标（设置侧「默认」：与勾双保险、
    /// 措辞全 App 一种，DefaultModelPickerView 定版）
    var currentTag: String? = nil
    var monospaced: Bool = false
    var titleLineLimit: Int = 1
    /// nil ＝静态行；非 nil ＝整行按钮、点即选
    var onSelect: (() -> Void)? = nil

    var body: some View {
        if let onSelect {
            Button { onSelect() } label: { content }
                .buttonStyle(.odPressable)
                .accessibilityAddTraits(
                    isCurrent ? .isSelected : []
                )
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            VStack(
                alignment: .leading,
                spacing: OneDayMetrics.spacingMicro
            ) {
                Text(title)
                    .font(
                        monospaced
                            ? .system(.callout, design: .monospaced)
                            : .body
                    )
                    .foregroundStyle(Palette.ink)
                    .lineLimit(titleLineLimit)
                if let subline {
                    Text(subline)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Spacer(minLength: OneDayMetrics.spacingS)
            if let currentTag {
                Text(currentTag)
                    .font(.footnote)
                    .foregroundStyle(Palette.successText)
            }
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.primary)
            }
        }
        .contentShape(Rectangle())
    }
}
