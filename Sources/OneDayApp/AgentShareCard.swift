import Foundation
import OneDayDesign
import SwiftUI

/// 智能体分享名片（0.36.22）：枢纽页头分享圆钮的内
/// 容——名称＋头像＋服务器域名，仅此三件。
///
/// 红线（规格明文）：不含密钥、令牌、完整连接串。
/// 执行形态：名片图是下方卡面视图的离屏渲染（卡面
/// 只有头像/名/域名三元素）；域名只经
/// AgentServerHost.extract（只出 host）；纯文本兜
/// 底只经 AgentShareCardText.make（入参只有名与
/// host，凭据结构上进不来）。旧 shareText（含当前
/// 模型、无域名）自此退出分享面。
///
/// 分享载荷形态（CI 修订）：初版用自定义
/// Transferable 喂 ShareLink(item:)，CI 实证编译
/// 器不认账（run 42876149998：候选只列 URL/String
/// 两个具体签名、AgentHubView.swift:227 报 no
/// exact matches，一致性本体却无报错）；改走编译
/// 器原生支持的 URL 形态——名片图渲染后落盘、按
/// 文件 URL 分享，载荷仍是同一张名片图。
struct AgentShareItem {
    let fileURL: URL

    /// 组装名片：渲染或落盘失败回 nil，调用方回落
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
        guard let url = persistCardPNG(png) else { return nil }
        return AgentShareItem(fileURL: url)
    }

    /// 名片图落盘（固定路径覆盖写）：分享面板按文
    /// 件 URL 读图，文件名即面板里显示的图名
    private static func persistCardPNG(_ png: Data) -> URL? {
        let fm = FileManager.default
        guard let caches = fm.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = caches.appendingPathComponent(
            "AgentShareCard", isDirectory: true
        )
        do {
            try fm.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let url = dir.appendingPathComponent(
                "OneDay-Agent-Card.png"
            )
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// 名片卡面（600×360pt）：头像＋名＋域名，一眼是
/// 谁、连的哪台服务器，别的一概不上卡。
struct AgentShareCardView: View {
    let name: String
    let host: String?
    let avatarImage: Image

    var body: some View {
        // 名片成图构图值（头像 132 与文字区的固定间距，
        // 导出图版式自洽、不随 App 间距梯队走，C5 清点注记）
        HStack(spacing: 28) {
            avatarImage
                .resizable()
                .scaledToFill()
                .frame(width: 132, height: 132)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Palette.hairline, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: OneDayMetrics.cardInnerGap) {
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
