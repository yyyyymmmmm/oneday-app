import OneDayCore
import OneDayDesign
import SwiftUI

/// 顶栏模型选择面（§153 B1）：系统 List 分段——段头
/// ＝服务商（网关段「默认服务商」），段内模型行＝执
/// 行模型名＋来源/默认小字，当前本会话执行行带系统
/// checkmark。顶部搜索跨组过滤（Core filtered 唯一
/// 口径）。页脚一句作用域人话（报告 §四：比 Studio
/// 多做一步——「只对这条对话生效」写在明处）。点行
/// 即落本会话账并关面（回调由 ChatView 注入）；本面
/// 不读不写服务端默认、不发网络请求。分组为空（清
/// 单未就绪）时呈安静空态，不拿假数据冒充。
/// §158 增补：分组可折叠（段头可点、账与设置面同
/// 源）、回执内置行收进「未配置的服务商」组默认收
/// 起、组头长按可隐藏（网关组与内置组；隐藏＝本机
/// 呈现治理，写入走宿主回调 hideGroup，确认口径在
/// 宿主侧）。
struct ChatModelPickerView: View {
    let groups: [ChatModelGroup]
    let current: ChatModelChoice
    let onSelect: (ChatModelChoice) -> Void
    /// 隐藏一组（宿主＝ChatView→AppState 落账）；nil
    /// 时不给隐藏动作（枢纽等只读复用面）。收纳组
    /// （未配置的服务商）隐藏按行原组逐家回调——本
    /// 回调收到的恒是回执原组、不是收纳组本体
    var onHideGroup: ((ChatModelGroup) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// 分组折叠账（§158）：与设置面共账同键（键＝组
    /// 标题），Core SectionCollapseState 唯一口径
    @AppStorage(SectionCollapseStorageKeys.modelSections)
    private var collapseData: Data = Data()

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 呈现拼装（§158）：先过搜索过滤，再分拣内置行
    /// 收成一组；搜索态不收纳（查到哪组就摊开哪组，
    /// 不让用户在搜索结果里再翻一层）
    private var displayGroups: [DisplayGroup] {
        let filtered = ChatModelGroups.filtered(groups, query: query)
        if isSearching {
            return filtered.map {
                DisplayGroup(group: $0, isBuiltinBucket: false)
            }
        }
        let parts = ProviderGroupVisibility.partition(filtered)
        var result = parts.main.map {
            DisplayGroup(group: $0, isBuiltinBucket: false)
        }
        if let bucket = ProviderGroupVisibility.bucketGroup(parts.builtin) {
            // 收纳组内每行的原服务商名随行带走（行副行
            // 拼名用），组本体标题换收纳标题；原组清单
            // 随组带走供长按逐家隐藏与恢复名单对账
            let named = parts.builtin.flatMap { source in
                source.choices.map {
                    DisplayChoice(choice: $0, originTitle: source.title)
                }
            }
            result.append(DisplayGroup(
                group: bucket, isBuiltinBucket: true,
                choices: named, sourceGroups: parts.builtin
            ))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayGroups) { display in
                    Section {
                        if !isGroupCollapsed(display) {
                            ForEach(display.rows) { item in
                                row(item.choice, origin: item.originTitle)
                            }
                        }
                    } header: {
                        groupHeader(display)
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
                } else if displayGroups.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - §158 折叠与隐藏

    /// 一组的呈现形态：本体组＋是否内置收纳组＋行级
    /// 原名（收纳组行需要知道自己来自哪家）
    private struct DisplayGroup: Identifiable {
        var group: ChatModelGroup
        var isBuiltinBucket: Bool
        var choices: [DisplayChoice]? = nil
        /// 收纳组的原组清单（逐家隐藏/计数对账用）
        var sourceGroups: [ChatModelGroup] = []
        var id: String { group.title }
        var rows: [DisplayChoice] {
            choices ?? group.choices.map {
                DisplayChoice(choice: $0, originTitle: nil)
            }
        }
    }

    private struct DisplayChoice: Identifiable {
        var choice: ChatModelChoice
        var originTitle: String?
        var id: String { choice.id }
    }

    /// 折叠判定：搜索态恒展开；其余查账，缺键走 Core
    /// 默认态（主列展开／内置收纳组收起）
    /// §179.3：删除当前组强制展开逻辑——用户应能折叠
    /// 任何组（含当前模型所在组），尊重 toggle 操作
    private func isGroupCollapsed(_ display: DisplayGroup) -> Bool {
        if isSearching { return false }
        return SectionCollapseState.isCollapsed(
            key: display.group.title,
            in: SectionCollapseState.decode(collapseData),
            defaultCollapsed: ProviderGroupVisibility.defaultCollapsed(
                isBuiltinBucket: display.isBuiltinBucket
            )
        )
    }

    private func toggleGroup(_ display: DisplayGroup) {
        withAnimation(.smooth(duration: 0.3)) {
            collapseData = SectionCollapseState.encode(
                SectionCollapseState.toggled(
                    key: display.group.title,
                    in: SectionCollapseState.decode(collapseData),
                    defaultCollapsed:
                        ProviderGroupVisibility.defaultCollapsed(
                            isBuiltinBucket: display.isBuiltinBucket
                        )
                )
            ) ?? collapseData
        }
    }

    /// 段头：标题＋计数＋chevron，整行可点（命中高
    /// ≥44）；长按隐藏分两形——普通可隐藏组（网关组，Core
    /// 组键非 nil）整组一项；收纳组按原组逐家列（收
    /// 纳组不是一家、没有自己的组键，藏的是行背后的
    /// 原组）；具名组不给（删除走设置页既有删除服务商）
    @ViewBuilder
    private func groupHeader(_ display: DisplayGroup) -> some View {
        let collapsed = isGroupCollapsed(display)
        let header = HStack(spacing: 6) {
            Text(display.group.title)
            Text("\(display.rows.count)")
                .foregroundStyle(Palette.inkSecondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .rotationEffect(.degrees(collapsed ? -90 : 0))
                .animation(.smooth(duration: 0.25), value: collapsed)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { toggleGroup(display) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.group.title)
        .accessibilityValue(collapsed ? "已折叠" : "已展开")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggleGroup(display) }
        if let onHideGroup {
            if display.isBuiltinBucket {
                header.contextMenu {
                    ForEach(display.sourceGroups) { source in
                        Button(role: .destructive) {
                            onHideGroup(source)
                        } label: {
                            Label(
                                L10n.format(
                                    "隐藏 %@",
                                    source.title
                                ),
                                systemImage: "eye.slash"
                            )
                        }
                    }
                }
            } else if ProviderGroupVisibility.groupKey(
                for: display.group
            ) != nil {
                header.contextMenu {
                    Button(role: .destructive) {
                        onHideGroup(display.group)
                    } label: {
                        Label("从列表中隐藏", systemImage: "eye.slash")
                    }
                }
            } else {
                header
            }
        } else {
            header
        }
    }

    /// 模型行：名（执行值原文——具名服务商的模型名
    /// 就是它在自家目录里的名字）＋副行（来源标注，
    /// 默认行加「默认」），当前行尾系统 checkmark；
    /// 收纳组内的行副行带原服务商名（origin 非 nil）
    private func row(
        _ choice: ChatModelChoice, origin: String?
    ) -> some View {
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
                    if let subline = subline(for: choice, origin: origin) {
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

    /// 副行拼装：「经网关」/「直连 · 名」＋默认标记；
    /// 内置收纳组行没有来源标注时以原服务商名兜底
    /// （否则同名模型在收纳组里分不清是谁家的）
    private func subline(
        for choice: ChatModelChoice, origin: String?
    ) -> String? {
        var parts: [String] = []
        if let label = choice.sourceLabel {
            parts.append(L10n.string(label))
        } else if let origin {
            parts.append(origin)
        }
        if choice.isDefault {
            parts.append(L10n.string("默认"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
