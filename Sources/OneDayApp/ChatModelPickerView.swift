import OneDayCore
import OneDayDesign
import SwiftUI

/// 顶栏模型选择面（§149 B1）：系统 List 分段——段头
/// ＝服务商（网关段「默认服务商」），段内模型行＝执
/// 行模型名＋来源/默认小字，当前本会话执行行带系统
/// checkmark。顶部搜索跨组过滤（Core filtered 唯一
/// 口径）。页脚一句作用域人话（报告 §四：比 Studio
/// 多做一步——「只对这条对话生效」写在明处）。点行
/// 即落本会话账并关面（回调由 ChatView 注入）；本面
/// 不读不写服务端默认、不发网络请求。分组为空（清
/// 单未就绪）时呈安静空态，不拿假数据冒充。
struct ChatModelPickerView: View {
    let groups: [ChatModelGroup]
    let current: ChatModelChoice
    let onSelect: (ChatModelChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var visibleGroups: [ChatModelGroup] {
        ChatModelGroups.filtered(groups, query: query)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleGroups) { group in
                    Section {
                        ForEach(group.choices) { choice in
                            row(choice)
                        }
                    } header: {
                        Text(group.title)
                    }
                }
                Section {
                    Text("只对这条对话生效")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索模型")
            )
            .navigationTitle("模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView(
                        "还没有可用的模型",
                        systemImage: "cpu",
                        description: Text("连接服务器后，这里会列出全部服务商的模型。")
                    )
                } else if visibleGroups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 模型行：名（执行值原文——具名服务商的模型名
    /// 就是它在自家目录里的名字）＋副行（来源标注，
    /// 默认行加「默认」），当前行尾系统 checkmark
    private func row(_ choice: ChatModelChoice) -> some View {
        let isCurrent = choice == current
        return Button {
            onSelect(choice)
        } label: {
            HStack(spacing: OneDayMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(choice.model)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    if let subline = subline(for: choice) {
                        Text(subline)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.odPressable)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// 副行拼装：「经网关」/「直连 · 名」＋默认标记
    private func subline(for choice: ChatModelChoice) -> String? {
        var parts: [String] = []
        if let label = choice.sourceLabel {
            parts.append(L10n.string(label))
        }
        if choice.isDefault {
            parts.append(L10n.string("默认"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
