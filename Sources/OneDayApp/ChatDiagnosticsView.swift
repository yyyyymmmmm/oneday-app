import OneDayCore
import OneDayDesign
import SwiftUI

/// 聊天诊断面（台账 189/190，设置支持组直达）
///
/// 本机聊天面探针的唯一可读面：ChatLagProbe 汇
/// 总、量测台积压、ChatDiagTrace 留痕此前只写不
/// 读（探针落 UserDefaults/os 日志、App 内无消
/// 费方，真机回读无门——182/190 两轮诊断共同点
/// 名的制度缺口），本面把四路读数收敛到一处：
/// ①卡顿探针汇总（喂入/托管/解码份额）②量测
/// 台积压（未量测行数与就地量测计数，190 验收
/// 证据）③当前主题气泡解析值（台账 188 证据出
/// 口：单档定版后填充/字色解析成何色，不再靠截
/// 图反推；184 的浓淡键原文读口随 188 删机制一
/// 并撤除——键已无消费方、原文读出只会误导）
/// ④诊断留痕全文（锚四值探针 anchorQuad 在此
/// 回读）。
/// 纪律：只读呈现、不写任何业务状态；读数在出
/// 现/手动刷新时快照，行文等宽小字、可选中复制
/// §493（D5）：关于页「内部实验」整节迁入本页末
/// 节——§374 施工旗＋崩溃报告收集/入口与本页同为
/// 内部取证面；开关本体与 @AppStorage 键随迁不
/// 改，副文案逐条压成一句（原增量喂入「默认关
/// 闭」与事实相反的文案一并改正：缺省开）
struct ChatDiagnosticsView: View {
    @State private var refreshTick = 0

    /// §374 施工旗（与聊天引擎同键同源，缺省全开；
    /// 关掉即回各步旧路，一个版本周期的回退口）
    @AppStorage(ChatListIncrementalFeature.defaultsKey)
    private var chatListIncrementalEnabled = true
    @AppStorage(ChatListSingleSectionFeature.defaultsKey)
    private var chatListSingleSectionEnabled = true
    @AppStorage(
        ChatListCoalesceWindowDropFeature.defaultsKey
    )
    private var chatListDropCoalesceWindow = true
    @AppStorage(
        ChatListSettleSingleBeatFeature.defaultsKey
    )
    private var chatListSettleSingleBeat = true
    @AppStorage(
        ChatListDrawerFreezeDropFeature.defaultsKey
    )
    private var chatListDropDrawerFreeze = true
    @AppStorage(
        ChatListScrollLedgerFeature.defaultsKey
    )
    private var chatListScrollLedger = true
    @AppStorage(
        ChatListSelectionKeyGuardFeature.defaultsKey
    )
    private var chatListSelectionKeyGuard = true
    /// §384 崩溃报告收集（与采集端同键同源，缺省开）
    @AppStorage(
        CrashCollectionFeature.defaultsKey
    )
    private var crashCollectionEnabled = true

    var body: some View {
        // refreshTick 入依赖：刷新钮自增即整面重读
        let _ = refreshTick
        List {
            Section {
                Text(ChatLagProbe.summaryLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                Text("卡顿探针")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(ChatNativeRowMeasureDesk.backlogLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                Text("量测台")
            }
            .listRowBackground(Palette.surface)

            Section {
                Text(bubbleLine())
                    .font(.metaMonospaced)
                    .textSelection(.enabled)
            } header: {
                Text("气泡解析（台账 188）")
            }
            .listRowBackground(Palette.surface)

            Section {
                let traces = ChatDiagTrace.snapshots
                if traces.isEmpty {
                    Text("暂无留痕")
                        .font(.footnote)
                        .foregroundStyle(
                            Palette.inkSecondary
                        )
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
                Text("诊断留痕")
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

    // MARK: - 内部实验（§493 自关于页迁入）

    /// 内部实验节：§374 施工旗七枚＋崩溃报告收集开
    /// 关＋崩溃报告入口。副文案逐条一句（T4）；节脚
    /// 一句（T6）
    private var labSection: some View {
        Section {
            labToggle(
                isOn: $chatListIncrementalEnabled,
                title: "聊天列表增量喂入",
                subtitle: "默认开启：消息列表改走变更集增量喂入，关掉即回全量喂入。"
            )
            labToggle(
                isOn: $chatListSingleSectionEnabled,
                title: "聊天列表单 section 布局",
                subtitle: "默认开启：消息列表走单 section 构造，关掉即回逐行 section 构造。"
            )
            labToggle(
                isOn: $chatListDropCoalesceWindow,
                title: "聊天列表落定拍直达施工",
                subtitle: "默认开启：落定拍不再攒时间窗、见账即施工，关掉即恢复时间窗合并。"
            )
            labToggle(
                isOn: $chatListSettleSingleBeat,
                title: "聊天列表停滚结清单拍",
                subtitle: "默认开启：停滚后一拍内结清全部待结账目，关掉即恢复拆拍结清。"
            )
            labToggle(
                isOn: $chatListDropDrawerFreeze,
                title: "聊天列表抽屉动画期直达应用",
                subtitle: "默认开启：抽屉动画期内到达的变更直接应用，关掉即恢复动画期冻结。"
            )
            labToggle(
                isOn: $chatListScrollLedger,
                title: "聊天列表滚动期记账降级",
                subtitle: "默认开启：滚动中变更只记账、停滚时当场应用，关掉即恢复现行滚动闸。"
            )
            labToggle(
                isOn: $chatListSelectionKeyGuard,
                title: "聊天列表选区单键暂缓",
                subtitle: "默认开启：正在选字的行更新先暂存、选区消失后补发，关掉即全部直达。"
            )
            Toggle(isOn: $crashCollectionEnabled) {
                labToggleLabel(
                    title: "崩溃报告收集",
                    subtitle: "默认开启：崩溃与卡死脱敏保存在本机，关掉即停止收集。"
                )
            }
            .onChange(of: crashCollectionEnabled) { _, newValue in
                CrashDiagnosticsCollector.shared.setEnabled(newValue)
            }
            NavigationLink(value: SettingsRoute.crashReports) {
                HStack(alignment: .top, spacing: OneDayMetrics.spacingSM) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(
                            size: FrameworkIcon.settingsGlyphSize,
                            weight: .regular
                        ))
                        .foregroundStyle(Palette.ink)
                        .frame(width: OneDayMetrics.iconSlot, alignment: .center)
                        .accessibilityHidden(true)
                    Text(L10n.string("崩溃报告"))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            }
        } header: {
            Text("内部实验")
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

    /// 气泡解析读数：当前主题浅/暗两档的填充与
    /// 字色解析值——与 Palette.userBubbleFill 同
    /// 一解析出口（ChatTheme.bubbleFill/bubble-
    /// Text 单档口径）。188 定版前此节兼读浓淡键
    /// 原文，键随机制删除后无原文可读，只剩解析
    /// 值供颜色争议取证
    private func bubbleLine() -> String {
        let theme = Palette.currentChatTheme
        func hex(_ value: UInt32) -> String {
            String(format: "#%06X", value)
        }
        return "主题 \(theme.displayName)（单档定死）"
            + "\n浅 填充 \(hex(theme.bubbleFill(dark: false)))"
            + " 字 \(hex(theme.bubbleText(dark: false)))"
            + "\n暗 填充 \(hex(theme.bubbleFill(dark: true)))"
            + " 字 \(hex(theme.bubbleText(dark: true)))"
    }
}
