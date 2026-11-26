import SwiftUI

/// 设置窗骨架（macOS 标准 Settings 场景，⌘, 打开）：
/// 地基棒只立「服务器」节的连接信息与断开动作；各设
/// 置节按对位表第 65–89 件在设置棒逐节接入，不在此
/// 先行摆空架子冒充全集。
struct MacSettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Form {
            Section("服务器") {
                if let config = session.config {
                    LabeledContent("当前服务器", value: config.host)
                    LabeledContent(
                        "Hermes 版本", value: session.hermesVersion ?? "—"
                    )
                    LabeledContent(
                        "可用模型", value: "\(session.modelCount) 个"
                    )
                    Button("断开连接", role: .destructive) {
                        session.disconnect()
                    }
                } else {
                    Text("尚未连接服务器。请在主窗口完成连接。")
                        .foregroundStyle(.secondary)
                }
            }
            Section("通用") {
                Text("外观、语言、语音、通知等设置节在设置棒按对位表逐节接入。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
