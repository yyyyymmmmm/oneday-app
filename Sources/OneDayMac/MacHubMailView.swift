import SwiftUI
import OneDayCore

/// 邮件面（棒 4，对位 #43）：iOS 注册表此格在未长
/// 出前不可达、HubSegmentID.mail 无活数据源（拟案
/// 盘点实查）；Mac 如实呈现未启用态，不摆假数据——
/// 与 iOS 现行行为一致，等服务端邮件面长出后两端
/// 同步接
struct MacHubMailView: View {
    let store: MacHubStore

    var body: some View {
        ContentUnavailableView(
            "邮件面尚未启用",
            systemImage: "envelope.open",
            description: Text(
                "服务端还没有邮件数据源，iOS 端此面同样不可达。本面不摆假数据，数据源长出后同步接入。"
            )
        )
    }
}
