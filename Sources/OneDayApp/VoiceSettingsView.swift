import OneDayDesign
import OneDayCore
import SwiftUI

/// 语音面（H2-a，台账 159）：设置 → 通用与偏好 →「语音」
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var appState
    private var speechPlayer: SpeechPlayer { .shared }
    @AppStorage(VoiceSpeechPreferences.autoReadKey)
    private var autoRead = false

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "speaker.wave.2.fill",
                tint: .orange,
                title: "回复朗读",
                subtitle: "由服务端语音引擎合成，支持单条朗读与新回复自动播报。",
                statusText: speechPlayer.availability.word,
                statusTone: availabilityTone
            )

            Section {
                Toggle(isOn: $autoRead) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        IconTile(symbol: "waveform", color: .orange, size: OneDayMetrics.iconSlot)
                        Text("自动朗读新回复")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            } header: {
                SettingsSectionHeader("播报偏好")
            } footer: {
                Text(availabilityFooter)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                SettingsValueRow(
                    symbol: "person.wave.2",
                    tint: .indigo,
                    title: "当前音色",
                    value: providerText
                )
            } header: {
                SettingsSectionHeader("音色")
            } footer: {
                Text("音色由服务端配置决定，如需切换请在服务端修改语音配置。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await speechPlayer.refreshAvailability(
                appState: appState, force: true
            )
        }
    }

    private var availabilityTone: SettingsStatusTone {
        switch speechPlayer.availability {
        case .available: return .healthy
        case .unavailable: return .warning
        case .unknown: return .neutral
        }
    }

    private var availabilityFooter: String {
        switch speechPlayer.availability {
        case .available:
            return "在对话里长按助手回复，选「朗读」即可听；自动朗读开启后，新回复落定会自动读出来。"
        case .unavailable:
            return "这台服务器还没开通朗读（合成组件未安装或未启用），长按菜单里不会出现「朗读」。"
        case .unknown:
            return "暂时读不到服务端的语音配置，连上服务器后会自动刷新。"
        }
    }

    private var providerText: String {
        SpeechProviderDisplay.name(for: speechPlayer.lastProvider)
    }
}
