import SwiftUI
import AppKit
import UserNotifications
import OneDayCore
import OneDayDesign

/// 通知、互动与语音设置页（棒 5 / mac-07，对位 #68/#69/#70/#91）：
/// - 分类提醒四键与 Core NotificationTier.Category 逐字同键
/// - 推送就绪自检如实呈现本机授权状态与 APNs 条件棒现状
/// - 互动两开关与 Core ChatReactionsFloatingBarFeature /
///   ChatReactionsAISelfFeature 逐字同键，AI 反应按能力位门控
/// - 回复朗读与 Core VoiceSpeechPreferences.autoReadKey 同键
struct MacSettingsNotificationsPane: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("notify.category.approval.enabled")
    private var approvalEnabled = true
    @AppStorage("notify.category.runCompleted.enabled")
    private var runCompletedEnabled = true
    @AppStorage("notify.category.failure.enabled")
    private var failureEnabled = true
    @AppStorage("notify.category.system.enabled")
    private var systemEnabled = true

    @AppStorage(ChatReactionsFloatingBarFeature.defaultsKey)
    private var floatingBarEnabled = true
    @AppStorage(ChatReactionsAISelfFeature.defaultsKey)
    private var aiSelfReactionsEnabled = true

    @AppStorage(VoiceSpeechPreferences.autoReadKey)
    private var autoRead = false

    @State private var authStatusText = "检查中…"
    @State private var voiceStatusText = "未检查"
    @State private var voiceProviderText = "—"

    private var aiSelfRowVisible: Bool {
        SelfReactionsSettingsRowPolicy.isRowVisible(
            availability: CapabilityNegotiation.selfReactionsAvailability(
                session.capabilities
            )
        )
    }

    var body: some View {
        Form {
            Section {
                categoryToggle(.approval, isOn: $approvalEnabled)
                categoryToggle(.failure, isOn: $failureEnabled)
                categoryToggle(.runCompleted, isOn: $runCompletedEnabled)
                categoryToggle(.system, isOn: $systemEnabled)
            } header: {
                Text("分类提醒")
            } footer: {
                Text("Mac 端当前通过本地通知（M3 保底段）投递待批提醒，可在通知横幅直接批准或拒绝。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Section("推送就绪状态") {
                LabeledContent("系统通知授权", value: authStatusText)
                LabeledContent(
                    "APNs 远程推送",
                    value: "未启用（服务端已支持，需付费 Apple Developer 签名与 .p8 密钥）"
                )
                Button("打开 macOS 通知设置") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("消息互动") {
                Toggle(isOn: $floatingBarEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("悬停快捷表情条")
                        Text("鼠标悬停在消息气泡旁时显示表情反应与复制快捷条")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
                if aiSelfRowVisible {
                    Toggle(isOn: $aiSelfReactionsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI 自反应角标")
                            Text("在用户消息气泡角落显示智能体的情绪回应角标")
                                .font(.caption)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
            }

            Section {
                Toggle("自动朗读新回复", isOn: $autoRead)
                LabeledContent("服务端语音引擎", value: voiceStatusText)
                LabeledContent("当前音色提供方", value: voiceProviderText)
            } header: {
                Text("语音朗读")
            } footer: {
                Text("语音合成由服务端配置决定，本机开关与 iOS 端同键。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await refreshNotificationAuth()
            await refreshVoiceConfig()
        }
    }

    private func categoryToggle(
        _ category: NotificationTier.Category, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Text(category.label())
                Text(NotificationTier.tier(for: category).label())
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
    }

    private func refreshNotificationAuth() async {
        let settings = await UNUserNotificationCenter.current()
            .notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: authStatusText = "已授权"
        case .denied: authStatusText = "已拒绝（请在系统设置开启）"
        case .notDetermined: authStatusText = "未请求（首次待批出现时申请）"
        case .provisional: authStatusText = "临时静默授权"
        case .ephemeral: authStatusText = "临时授权"
        @unknown default: authStatusText = "未知"
        }
    }

    private func refreshVoiceConfig() async {
        guard let config = session.config, let key = session.apiKey else {
            voiceStatusText = "未连接服务器"
            return
        }
        do {
            let vc = try await session.chatClient.voiceConfig(
                config: config, apiKey: key
            )
            let avail = VoiceAvailability.assess(config: vc)
            voiceStatusText = avail.word
            voiceProviderText = SpeechProviderDisplay.name(for: vc.tts?.mode)
        } catch {
            voiceStatusText = "未读取到配置"
        }
    }
}
