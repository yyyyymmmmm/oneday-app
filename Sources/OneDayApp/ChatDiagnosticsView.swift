import OneDayCore
import OneDayDesign
import SwiftUI

/// 聊天渲染诊断面（扁平叶子页，不再套娃嵌套崩溃报告）
struct ChatDiagnosticsView: View {
    @State private var refreshTick = 0
    @State private var showInternalSwitches = false

    @AppStorage(ChatListIncrementalFeature.defaultsKey)
    private var chatListIncrementalEnabled = true
    @AppStorage(ChatListSingleSectionFeature.defaultsKey)
    private var chatListSingleSectionEnabled = true
    @AppStorage(ChatListCoalesceWindowDropFeature.defaultsKey)
    private var chatListDropCoalesceWindow = true
    @AppStorage(ChatListSettleSingleBeatFeature.defaultsKey)
    private var chatListSettleSingleBeat = true
    @AppStorage(ChatListDrawerFreezeDropFeature.defaultsKey)
    private var chatListDropDrawerFreeze = true
    @AppStorage(ChatListScrollLedgerFeature.defaultsKey)
    private var chatListScrollLedger = true
    @AppStorage(ChatListSelectionKeyGuardFeature.defaultsKey)
    private var chatListSelectionKeyGuard = true
    @AppStorage(CrashCollectionFeature.defaultsKey)
    private var crashCollectionEnabled = true

    var body: some View {
        let _ = refreshTick
        List {
            SettingsHeroCard(
                symbol: "doc.text.magnifyingglass",
                tint: .indigo,
                title: "聊天渲染诊断",
                subtitle: "实时查看列表帧率探针、行高量测积压与本机诊断留痕。"
            )

            Section {
                Text(ChatLagProbe.summaryLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                SettingsSectionHeader("卡顿探针")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(ChatNativeRowMeasureDesk.backlogLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                SettingsSectionHeader("量测台")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(bubbleLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                SettingsSectionHeader("气泡解析")
            }
            .listRowBackground(Palette.surface)

            Section {
                let traces = ChatDiagTrace.snapshots
                if traces.isEmpty {
                    Text("暂无留痕")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                } else {
                    ForEach(
                        Array(traces.reversed().enumerated()),
                        id: \.offset
                    ) { _, line in
                        Text(line)
                            .font(.metaMonospaced)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                SettingsSectionHeader("诊断留痕")
            }
            .listRowBackground(Palette.surface)

            labSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("聊天诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新") { refreshTick += 1 }
            }
        }
    }

    private var labSection: some View {
        Section {
            Toggle(isOn: $crashCollectionEnabled) {
                labToggleLabel(
                    title: "崩溃报告收集",
                    subtitle: "脱敏保存在本机，关闭即停止收集。"
                )
            }
            .onChange(of: crashCollectionEnabled) { _, newValue in
                CrashDiagnosticsCollector.shared.setEnabled(newValue)
            }

            DisclosureGroup("内部渲染实验开关（仅排障使用）", isExpanded: $showInternalSwitches) {
                labToggle(
                    isOn: $chatListIncrementalEnabled,
                    title: "聊天列表增量喂入",
                    subtitle: "默认开启：按变更集增量更新消息列表。"
                )
                labToggle(
                    isOn: $chatListSingleSectionEnabled,
                    title: "单 section 布局",
                    subtitle: "默认开启：消息列表走单 section 构造。"
                )
                labToggle(
                    isOn: $chatListDropCoalesceWindow,
                    title: "落定拍直达施工",
                    subtitle: "默认开启：落定拍见账即施工。"
                )
                labToggle(
                    isOn: $chatListSettleSingleBeat,
                    title: "停滚单拍结清",
                    subtitle: "默认开启：停滚后一拍内结清待结账目。"
                )
                labToggle(
                    isOn: $chatListDropDrawerFreeze,
                    title: "抽屉动画期直达应用",
                    subtitle: "默认开启：抽屉动画期内到达的变更直接应用。"
                )
                labToggle(
                    isOn: $chatListScrollLedger,
                    title: "滚动期记账降级",
                    subtitle: "默认开启：滚动中变更仅记账、停滚即应用。"
                )
                labToggle(
                    isOn: $chatListSelectionKeyGuard,
                    title: "选区单键暂缓",
                    subtitle: "默认开启：选字期间暂缓该行重配。"
                )
            }
            .font(.rowTitleL)
            .foregroundStyle(Palette.ink)
        } header: {
            SettingsSectionHeader("采集与排障")
        }
        .listRowBackground(Palette.surface)
    }

    private func labToggle(
        isOn: Binding<Bool>, title: String, subtitle: String
    ) -> some View {
        Toggle(isOn: isOn) {
            labToggleLabel(title: title, subtitle: subtitle)
        }
    }

    private func labToggleLabel(
        title: String, subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(L10n.string(title))
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            Text(L10n.string(subtitle))
                .font(.rowSubtitle)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private func bubbleLine() -> String {
        let theme = Palette.currentChatTheme
        func hex(_ value: UInt32) -> String {
            String(format: "#%06X", value)
        }
        return "主题 \(theme.displayName)"
            + "\n浅 填充 \(hex(theme.bubbleFill(dark: false)))"
            + " 字 \(hex(theme.bubbleText(dark: false)))"
            + "\n暗 填充 \(hex(theme.bubbleFill(dark: true)))"
            + " 字 \(hex(theme.bubbleText(dark: true)))"
    }
}
