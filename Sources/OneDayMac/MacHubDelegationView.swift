import SwiftUI
import OneDayCore

/// 委派面（棒 4，对位 #48）：路由全量呈现（当前后
/// 端/后端清单/模型路线/档案路线），切换与设默认
/// 都走先读后改＋回读对账（成败以 routing 回读为
/// 准，与 iOS 同口径）；呈现直接读原始路由文档，
/// 未知字段不丢
struct MacHubDelegationView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore

    var body: some View {
        HubScroll {
            if let raw = store.routingRaw {
                let configured = raw.hubFirstStr(
                    ["configured", "backend"]
                ) ?? ""
                HubSectionHeader(title: "当前后端")
                HubKVView(label: "后端", value: configured)
                if let reason = raw.hubFirstStr(["blocked_reason"]) {
                    Text("当前后端在本机跑不了：\(reason)")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                let backends = raw.hubFirstList(["backends"])
                HubSectionHeader(
                    title: "后端清单", count: backends.count
                )
                ForEach(
                    Array(backends.enumerated()), id: \.offset
                ) { _, backend in
                    let name = backend.hubFirstStr(["name"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(backend.hubFirstStr(["label", "name"])
                                ?? name)
                                .font(.callout.weight(.medium))
                            Text(backend.hubFirstStr(
                                ["description", "reason"]
                            ) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if name == configured {
                            Text("当前")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else if backend.hubBool("available") ?? true {
                            Button("切换") {
                                Task {
                                    await store.setBackend(
                                        session: session, backend: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Text("不可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Divider()
                }
                let modelMap = raw.hubDict["model_map"] ?? .null
                let options = modelMap.hubFirstList(["options"])
                let modelDefault = modelMap.hubStr("default")
                HubSectionHeader(
                    title: "模型路线", count: options.count
                )
                ForEach(
                    Array(options.enumerated()), id: \.offset
                ) { _, option in
                    let name = option.hubFirstStr(["name", "id"]) ?? ""
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.callout.weight(.medium))
                            Text(option.hubFirstStr(
                                ["description", "model"]
                            ) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if name == modelDefault {
                            Text("默认")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Button("设为默认") {
                                Task {
                                    await store.setModelRouteDefault(
                                        session: session, name: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Divider()
                }
                let profileRoutes = raw.hubDict["profile_routes"]
                    ?? .null
                let profiles = profileRoutes.hubFirstList(["profiles"])
                let profileDefault = profileRoutes.hubStr("default")
                HubSectionHeader(
                    title: "档案路由", count: profiles.count
                )
                ForEach(
                    Array(profiles.enumerated()), id: \.offset
                ) { _, route in
                    let name = route.hubFirstStr(
                        ["profile", "name", "id"]
                    ) ?? ""
                    HStack(spacing: 8) {
                        Text(name).font(.callout.weight(.medium))
                        Spacer()
                        if name == profileDefault {
                            Text("默认")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Button("设为默认") {
                                Task {
                                    await store.setProfileRouteDefault(
                                        session: session, name: name
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "委派路由暂不可用。")
            }
        }
    }
}
