import SwiftUI
import OneDayCore

/// 设置窗（macOS 标准 Settings 场景，⌘, 打开）：
/// 棒 1 补两节——通用节的身份（#65）与服务器节的
/// 当前服务器（#74）＋登录会话与短时票据（#75）；
/// 其余设置节按对位表在设置棒逐节接入，不摆空架子。
struct MacSettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Form {
            Section("通用") {
                LabeledContent(
                    "智能体名",
                    value: session.agentDisplayName
                        ?? AgentName.fallback
                )
                LabeledContent(
                    "当前档案",
                    value: session.activeProfileName ?? "—"
                )
                Text("外观、语言、语音、通知等设置节在设置棒按对位表逐节接入。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("服务器") {
                if let config = session.config {
                    LabeledContent("当前服务器", value: config.host)
                    LabeledContent(
                        "服务器地址", value: config.baseString
                    )
                    LabeledContent(
                        "Hermes 版本",
                        value: session.hermesVersion ?? "—"
                    )
                    LabeledContent(
                        "可用模型",
                        value: "\(session.modelCount) 个"
                    )
                    LabeledContent(
                        "登录会话", value: "面板密码登录 · 密钥已存钥匙串"
                    )
                    LabeledContent(
                        "短时票据", value: shortLivedTokenText
                    )
                    Button("断开连接", role: .destructive) {
                        session.disconnect()
                    }
                } else {
                    Text("尚未连接服务器。请在主窗口完成连接。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    /// 短时票据呈现（#75）：能力位三态如实报——支
    /// 持/未广告/未读取，不把未读到说成不支持
    private var shortLivedTokenText: String {
        switch session.shortLivedTokensSupported {
        case .some(true):
            return "服务端支持（当前会话使用长效密钥）"
        case .some(false):
            return "服务端未启用"
        case .none:
            return "未读取到能力信息"
        }
    }
}
