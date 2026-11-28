import OneDayCore
import OneDayDesign
import SwiftUI

/// 语音与 TTS 引擎设置（Hermes v0.23.0 10 引擎音色 + Client-Direct 全双工语音配置）
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var speechPlayer: SpeechPlayer { .shared }
    @AppStorage(VoiceSpeechPreferences.autoReadKey)
    private var autoRead = false

    private struct TTSEngineOption: Identifiable, Hashable {
        let id: String
        let name: String
        let defaultVoice: String
    }

    private static let ttsEngines: [TTSEngineOption] = [
        .init(id: "edge", name: "Edge TTS（免费）", defaultVoice: "zh-CN-XiaoxiaoNeural"),
        .init(id: "openai", name: "OpenAI TTS", defaultVoice: "alloy"),
        .init(id: "elevenlabs", name: "ElevenLabs", defaultVoice: "Rachel"),
        .init(id: "kokoro", name: "Kokoro（本地高速）", defaultVoice: "zf_xiaobei"),
        .init(id: "qwen", name: "Qwen CosyVoice", defaultVoice: "longxiaochun"),
        .init(id: "cartesia", name: "Cartesia Sonic", defaultVoice: "sonic-multilingual"),
        .init(id: "google", name: "Google Cloud TTS", defaultVoice: "cmn-CN-Wavenet-A"),
        .init(id: "azure", name: "Azure Speech", defaultVoice: "zh-CN-XiaoyiNeural"),
        .init(id: "piper", name: "Piper（离线轻量）", defaultVoice: "zh_CN-huayan-medium"),
        .init(id: "macos_say", name: "macOS Say（宿主机）", defaultVoice: "Tingting"),
    ]

    @State private var selectedEngine = "edge"
    @State private var voiceName = "zh-CN-XiaoxiaoNeural"
    @State private var speechRate: Double = 1.0
    @State private var fullDuplexEnabled = false
    @State private var vadEnabled = true
    @State private var sttEngine = "whisper"
    @State private var isSaving = false
    @State private var saveNotice: String?
    @State private var isError = false

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "speaker.wave.2.fill",
                tint: Palette.tintOrangeInk,
                title: "语音与全双工通话",
                subtitle: "管理 Hermes 10 大 TTS 语音引擎、音色语速，以及 Client-Direct 低延迟全双工语音通话。",
                statusText: fullDuplexEnabled ? "全双工已开" : speechPlayer.availability.word,
                statusTone: fullDuplexEnabled ? .healthy : availabilityTone
            )

            Section {
                Toggle(isOn: $autoRead) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "waveform", color: Palette.tintSkyInk)
                        Text("自动朗读新回复")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .tint(Palette.primary)
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                Toggle(isOn: $fullDuplexEnabled) {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "phone.wave.2.fill", color: Palette.tintGreenInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Client-Direct 全双工语音")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                            Text("支持语音打断（Barge-in）与低延迟直连通话")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .tint(Palette.primary)
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                if fullDuplexEnabled {
                    Toggle(isOn: $vadEnabled) {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "ear.badge.waveform", color: Palette.tintLavenderInk)
                            Text("端侧语音活动检测（VAD）")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .tint(Palette.primary)
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)

                    Picker(selection: $sttEngine) {
                        Text("Whisper（服务端）").tag("whisper")
                        Text("Apple 端侧识别").tag("apple_speech")
                        Text("Deepgram 实时流").tag("deepgram")
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            SettingsRowIcon(symbol: "mic.fill", color: Palette.tintOrangeInk)
                            Text("语音识别引擎（STT）")
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
            } header: {
                SettingsSectionHeader("播报与全双工")
            } footer: {
                Text(availabilityFooter)
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)

            Section {
                Picker(selection: $selectedEngine) {
                    ForEach(Self.ttsEngines) { engine in
                        Text(engine.name).tag(engine.id)
                    }
                } label: {
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(symbol: "person.wave.2.fill", color: Palette.tintLavenderInk)
                        Text("TTS 合成引擎")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .onChange(of: selectedEngine) { _, newID in
                    if let matched = Self.ttsEngines.first(where: { $0.id == newID }),
                       voiceName.isEmpty || Self.ttsEngines.contains(where: { $0.defaultVoice == voiceName }) {
                        voiceName = matched.defaultVoice
                    }
                }

                LabeledContent("音色 ID") {
                    TextField("输入音色标识", text: $voiceName)
                        .multilineTextAlignment(.trailing)
                        .font(.metaMonospaced)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("语速倍率")
                            .font(.rowTitleL)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(String(format: "%.2fx", speechRate))
                            .font(.metaMonospaced)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Slider(value: $speechRate, in: 0.75...1.5, step: 0.05)
                        .tint(Palette.primary)
                }
                .padding(.vertical, 4)

                Button {
                    Task { await saveVoiceConfig() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSaving ? "正在同步语音配置…" : "保存并应用到服务端")
                            .font(.rowTitleL.weight(.medium))
                            .foregroundStyle(Palette.primary)
                        Spacer()
                    }
                    .frame(minHeight: OneDayMetrics.settingsRowHeight)
                }
                .disabled(isSaving)
            } header: {
                SettingsSectionHeader("10 引擎音色配置")
            } footer: {
                if let saveNotice {
                    Text(saveNotice)
                        .font(.footnote)
                        .foregroundStyle(isError ? Palette.danger : Palette.successText)
                } else {
                    Text("当前已探测服务商：\(providerText)。保存后将写入 Hermes config.yaml 的 tts / voice 配置段。")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .listRowBackground(Palette.surface)
            .listRowInsets(OneDayMetrics.settingsRowInsets)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .animation(MotionTokens.resolved(MotionTokens.swap, reduceMotion: reduceMotion), value: fullDuplexEnabled)
        .navigationTitle("语音")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await speechPlayer.refreshAvailability(appState: appState, force: true)
            await loadVoiceConfig()
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
            return "长按回复可单条朗读；开启自动朗读后，新回复生成完成将自动播报。"
        case .unavailable:
            return "当前服务器尚未启用语音朗读功能，可在下方选择引擎并保存启用。"
        case .unknown:
            return "暂时无法读取语音配置，连接服务器后自动刷新。"
        }
    }

    private var providerText: String {
        SpeechProviderDisplay.name(for: speechPlayer.lastProvider)
    }

    private func loadVoiceConfig() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        guard let raw = try? await appState.client.rawConfig(config: config, apiKey: apiKey) else { return }
        if let tts = raw["tts"] as? [String: Any] {
            if let provider = tts["provider"] as? String, !provider.isEmpty {
                selectedEngine = provider
            }
            if let voice = tts["voice"] as? String, !voice.isEmpty {
                voiceName = voice
            }
            if let speed = tts["speed"] as? Double, speed >= 0.5, speed <= 2.0 {
                speechRate = speed
            }
        }
        if let voice = raw["voice"] as? [String: Any] {
            if let duplex = voice["full_duplex"] as? Bool {
                fullDuplexEnabled = duplex
            }
            if let vad = voice["vad_enabled"] as? Bool {
                vadEnabled = vad
            }
            if let stt = voice["stt_engine"] as? String, !stt.isEmpty {
                sttEngine = stt
            }
        }
    }

    private func saveVoiceConfig() async {
        guard let config = appState.config, let apiKey = appState.apiKey else { return }
        isSaving = true
        saveNotice = nil
        isError = false
        defer { isSaving = false }

        let ttsPatch: [String: Any] = [
            "provider": selectedEngine,
            "voice": voiceName.trimmingCharacters(in: .whitespacesAndNewlines),
            "speed": (speechRate * 100).rounded() / 100,
        ]
        let voicePatch: [String: Any] = [
            "full_duplex": fullDuplexEnabled,
            "vad_enabled": vadEnabled,
            "stt_engine": sttEngine,
        ]
        do {
            try await appState.client.updateConfig(
                config: config,
                apiKey: apiKey,
                values: ["tts": ttsPatch, "voice": voicePatch]
            )
            saveNotice = "语音与全双工配置已同步至服务端。"
            isError = false
            Haptics.success()
            await speechPlayer.refreshAvailability(appState: appState, force: true)
        } catch {
            saveNotice = (error as? HermesError)?.userMessage ?? "保存失败：\(error.localizedDescription)"
            isError = true
            Haptics.error()
        }
    }
}
