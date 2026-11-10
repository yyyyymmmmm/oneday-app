import CoreTransferable
import OneDayCore
import OneDayDesign
import SwiftUI
import UniformTypeIdentifiers

/// 智能体分享名片（0.36.22）：枢纽页头分享圆钮的内
/// 容——名称＋头像＋服务器域名，仅此三件。
///
/// 红线（规格明文）：不含密钥、令牌、完整连接串。
/// 执行形态：名片文本只经 AgentShareCardText.make
/// （入参只有名与 host，凭据结构上进不来）；名片图
/// 是下方卡面视图的离屏渲染（卡面只有头像/名/域名
/// 三元素）；域名只经 AgentServerHost.extract（只出
/// host）。旧 shareText（含当前模型、无域名）自此退
/// 出分享面。
struct AgentShareItem: Transferable {
    let text: String
    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.pngData
        }
        ProxyRepresentation(exporting: \.text)
    }

    /// 组装名片：渲染失败（无图）回 nil，调用方回落
    /// 纯文本分享——分享永不因渲染缺失而死
    @MainActor
    static func make(
        name: String, host: String?, avatarImage: Image
    ) -> AgentShareItem? {
        let card = AgentShareCardView(
            name: name, host: host, avatarImage: avatarImage
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let png = renderer.uiImage?.pngData() else { return nil }
        return AgentShareItem(
            text: AgentShareCardText.make(name: name, host: host),
            pngData: png
        )
    }
}

/// 名片卡面（600×360pt）：头像＋名＋域名，一眼是
/// 谁、连的哪台服务器，别的一概不上卡。
struct AgentShareCardView: View {
    let name: String
    let host: String?
    let avatarImage: Image

    var body: some View {
        HStack(spacing: 28) {
            avatarImage
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(name)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                if let host {
                    Text(host)
                        .font(.system(size: 26))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Text("OneDay 智能体")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(36)
        .frame(width: 600, height: 360, alignment: .leading)
        .background(Palette.surface)
    }
}
