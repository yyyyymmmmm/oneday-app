import SwiftUI
import OneDayCore

/// 档案面（棒 4，对位 #44）：档案清单＋切换激活＋
/// Soul 文档查看/编辑（写回后回读，与 iOS 档案面
/// 同口径）
struct MacHubProfilesView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "档案", count: store.profiles.count
            )
            if store.profiles.isEmpty {
                HubEmptyText(text: "暂无档案。")
            }
            ForEach(
                Array(store.profiles.enumerated()), id: \.offset
            ) { _, profile in
                let name = profile.hubFirstStr(["name", "id"]) ?? ""
                let active = profile.hubBool("active")
                    ?? profile.hubBool("is_active") ?? false
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.callout.weight(.medium))
                        if let desc = profile.hubFirstStr(
                            ["description", "model"]
                        ) {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if active {
                        Text("当前")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Button("设为当前") {
                            Task {
                                await store.activateProfile(
                                    session: session, name: name
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Soul") {
                        Task {
                            await store.loadSoul(
                                session: session, name: name
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            if let name = store.soulProfileName {
                HubSectionHeader(title: "Soul · \(name)")
                TextEditor(text: Binding(
                    get: { store.soulText },
                    set: { store.soulText = $0 }
                ))
                .font(.body)
                .frame(minHeight: 160)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                }
                HStack {
                    Spacer()
                    Button("保存 Soul") {
                        Task { await store.saveSoul(session: session) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
