import OneDayDesign
import OneDayCore
import SwiftUI

/// 语音面（H2-a，台账 159）：设置 → 服务器管理 →
/// 维护 →「语音」。本包只落朗读部分——可用性行（读
/// voice-config 组合判定、精修以 speak 实调为准）、
/// 自动朗读开关、音色只读展示。转写兜底段归 H2-b
/// （前置＝定版改判），不在本面留假开关；音色不做
/// 选择器——speak 入参只有 text、音色由服务端配置
/// 定死，做选择器是假控件（施工图缺件 3 明示）。
/// 数据口径：可用性与最近 provider 读 SpeechPlayer
/// 共享态（与聊天页长按朗读同一份），进面刷新一次
/// 配置；拉不到显「未知」，不造假。
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var appState
    private var speechPlayer: SpeechPlayer { .shared }
    @AppStorage(VoiceSpeechPreferences.autoReadKey)
    private var autoRead = false

    var body: some View {
        List {
            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("服务端朗读")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    StatusDot(color: availabilityColor)
                    Text(speechPlayer.availability.word)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())

                Toggle(isOn: $autoRead) {
                    Text("自动朗读新回复")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                sectionHeader("回复朗读")
            } footer: {
                Text(availabilityFooter)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)

            Section {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Text("当前音色")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)
                    Spacer(minLength: OneDayMetrics.spacingS)
                    Text(providerText)
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .contentShape(Rectangle())
            } header: {
                sectionHeader("音色")
            } footer: {
                Text("音色由服务端配置决定，在 App 里不能更换；想换音色要改服务端配置。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await speechPlayer.refreshAvailability(
                appState: appState, force: true
            )
        }
    }

    private var availabilityColor: Color {
        switch speechPlayer.availability {
        case .available: return Palette.success
        case .unavailable: return Palette.warning
        case .unknown: return Palette.inkMuted
        }
    }

    private var availabilityFooter: String {
        switch speechPlayer.availability {
        case .available:
            return "在对话里长按助手回复，选「朗读」即可听；自动朗读开启后，新回复落定会自动读出来。"
        case .unavailable:
            return "这台服务器还没开通朗读（合成组件没装或没启用），长按菜单里不会出现「朗读」。开通在服务端完成，App 这边不用改。"
        case .unknown:
            return "暂时读不到服务端的语音配置，状态未知；连上服务器后会自动刷新。"
        }
    }

    /// 音色展示：以实际合成 provider 为准（speak 回
    /// 执），没读过时只说由服务端决定，不编造音色名
    private var providerText: String {
        SpeechProviderDisplay.name(
            for: speechPlayer.lastProvider
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.sectionLabel)
            .foregroundStyle(Palette.inkSecondary)
            .textCase(nil)
    }

    private var settingsRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20)
    }
}
