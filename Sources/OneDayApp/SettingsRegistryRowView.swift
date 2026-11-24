import OneDayCore
import OneDayDesign
import SwiftUI

/// 注册表值行（AI 自主设置权一期，DESIGN §437）：
/// 基础型条目的五型通用渲染——控件形态随记录类型
/// （开关／选择器／文本框／数值框／文本块），值自记
/// 录回读（SettingsRegistryRowModel 的生效值口径）。
/// 一期只读：服务端无写端点、任何现行值存储一律不
/// 动，控件一律 disabled 呈只读态——可点而无效的假
/// 控件即僵尸，不做；写面随二期 AI 工具面同批打开。
/// 行盒口径与设置根页共用行组件同档（图标槽／行题
/// 字阶／行高／分隔线贯通图标左缘，0.36.3 口径）。
struct SettingsRegistryRowView: View {
    let record: SettingsRegistryRecord

    private var model: SettingsRegistryRowModel {
        SettingsRegistryRowModel(record: record)
    }

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            rowIcon(record.icon ?? "slider.horizontal.3")
            if model.kind == .textBlock {
                VStack(
                    alignment: .leading,
                    spacing: OneDayMetrics.spacingMicro
                ) {
                    titleText
                    Text(model.stringValue)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: OneDayMetrics.spacingS)
            } else {
                titleText
                Spacer(minLength: OneDayMetrics.spacingS)
                control
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .contentShape(Rectangle())
        // 分隔线贯通到图标左缘（0.36.3，与根页行同口径）
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var titleText: some View {
        Text(L10n.string(record.title))
            .font(.rowTitleL)
            .foregroundStyle(Palette.ink)
    }

    @ViewBuilder
    private var control: some View {
        switch model.kind {
        case .toggle:
            Toggle("", isOn: .constant(model.boolValue))
                .labelsHidden()
                .disabled(true)
        case .picker:
            Picker("", selection: .constant(model.stringValue)) {
                ForEach(model.options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(true)
        case .textField:
            TextField("", text: .constant(model.stringValue))
                .multilineTextAlignment(.trailing)
                .disabled(true)
        case .numberField:
            TextField(
                "", value: .constant(model.numberValue), format: .number
            )
            .multilineTextAlignment(.trailing)
            .disabled(true)
        case .textBlock:
            EmptyView()
        }
    }

    /// 行图标（与根页同走 IconTile 色块图标）
    private func rowIcon(_ name: String) -> some View {
        IconTile(
            symbol: name,
            color: Palette.primary,
            size: OneDayMetrics.iconSlot
        )
    }
}
