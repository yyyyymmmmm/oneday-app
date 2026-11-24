import OneDayCore
import OneDayDesign
import SwiftUI

/// 互动页（§503 新设叶子页）：长按反应浮排与 AI
/// 反应两个开关的家——原在外观页「回复呈现」节，
/// 该节随 §503 整节退役（流式/打字渐显定死常开、
/// 不再有呈现开关），两开关属行为类偏好、迁入本
/// 页与目录「互动」条目直达（归家依据见 §503：
/// 现行 IA 一叶子一关切，语音页是朗读语义不收）。
/// 两键与消费链一字不动：反应浮排键 chat.reac-
/// tions.floatingBar（Core ChatReactionsFloating-
/// BarFeature 单源，本页写、聊天页 messageMenu
/// 读；关＝长按回系统菜单「添加反应」子菜单）；
/// AI 反应键 chat.reactions.aiSelf（Core Chat-
/// ReactionsAISelfFeature 单源，本页写、聊天页角
/// 标判定读；关＝只隐藏本机呈现、数据不删、重开
/// 全量回来）。AI 反应行显隐由服务端能力位门控
/// （SelfReactionsSettingsRowPolicy，未探得/未广
/// 告整行不出——僵尸禁令），进页 .task 刷新能力
/// 协商结论（随两开关自外观页整段迁入）
struct ReactionSettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(ChatReactionsFloatingBarFeature.defaultsKey)
    private var floatingBarEnabled = true
    @AppStorage(ChatReactionsAISelfFeature.defaultsKey)
    private var aiSelfReactionsEnabled = true

    /// AI 反应行显隐（§432）：单读 AppState 的能力
    /// 协商结论，未探得/未广告恒不出
    private var aiSelfRowVisible: Bool {
        SelfReactionsSettingsRowPolicy.isRowVisible(
            availability: appState.selfReactionsAvailability
        )
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $floatingBarEnabled) {
                    Text(L10n.string("反应浮排"))
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                // §432：AI 反应行——服务端未广告
                // self_reactions 能力位时整行不出
                if aiSelfRowVisible {
                    Toggle(isOn: $aiSelfReactionsEnabled) {
                        Text(L10n.string("AI 反应"))
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                SettingsSectionHeader(L10n.string("消息反应"))
            } footer: {
                Text(reactionFooter)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .task {
            await appState.refreshSelfReactionsAvailability()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("互动")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 区脚（§503 自外观页旧「回复呈现」区脚拆出
    /// 反应半边、语义逐字保留）：AI 反应一句只在开
    /// 关行在场时拼入——行不在场不提不存在的开关；
    /// 关开关的语义写清（只关呈现、数据不删、重开
    /// 全量回来）
    private var reactionFooter: String {
        var text = L10n.string("反应浮排管长按消息时的反应入口：开着先浮出表情排，关掉回到菜单里的「添加反应」。")
        if aiSelfRowVisible {
            text += L10n.string("AI 反应管助手贴在你消息上的表情：关了只是本机不显示，记录还在，重新打开会全量回来。")
        }
        return text
    }
}
