import SwiftUI
import OneDayCore

/// 身份面（棒 4，对位 #42）：身份全档（名/当前头像/
/// 头像廊），头像图字节走 identity-bridge 图片口逐
/// 张拉取；preset 头像无字节、以色块格呈现（与网
/// 页端 2.17.1 修法同口径）
struct MacHubIdentityView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            if let identity = store.identity {
                let name = identity.hubFirstStr(
                    ["soulName", "name", "display_name"]
                )
                if let name {
                    HubKVView(label: "当前名", value: name)
                }
                let avatars = identity.hubFirstList(
                    ["avatars", "avatar_list"]
                )
                HubSectionHeader(title: "头像廊", count: avatars.count)
                if avatars.isEmpty {
                    HubJSONSummaryView(value: identity)
                } else {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(minimum: 64, maximum: 84),
                            spacing: 10
                        )],
                        alignment: .leading, spacing: 10
                    ) {
                        ForEach(
                            Array(avatars.enumerated()), id: \.offset
                        ) { _, avatar in
                            avatarCell(avatar)
                        }
                    }
                }
            } else {
                HubEmptyText(text: "身份数据暂不可用。")
            }
        }
    }

    @ViewBuilder
    private func avatarCell(_ avatar: JSONValue) -> some View {
        let id = avatar.hubFirstStr(["id", "avatar_id"]) ?? ""
        let kind = avatar.hubStr("kind") ?? "image"
        let isCurrent = avatar.hubBool("is_current") ?? false
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 56, height: 56)
                if kind == "image",
                   let data = store.avatarImages[id],
                   let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if kind == "image" {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
            }
            if isCurrent {
                Text("当前")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .task {
            if kind == "image" {
                await store.loadAvatar(session: session, id: id)
            }
        }
    }
}
