import SwiftUI
import OneDayCore

/// Webhooks 面（棒 4，对位 #55）：平台开关＋订阅清
/// 单（摘要无密钥）＋启停/删除＋新建（回执一次性密
/// 钥只在当次呈现、不落盘，与 iOS 同口径）
struct MacHubWebhooksView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newName = ""
    @State private var newURL = ""
    @State private var newEvents = ""
    @State private var oneTimeSecret: String?
    @State private var confirmDelete: String?

    var body: some View {
        HubScroll {
            if let page = store.webhooksPage {
                HStack(spacing: 8) {
                    Text(page.platformEnabled ? "平台已开启" : "平台未开启")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(
                            page.platformEnabled ? .green : .orange
                        )
                    if !page.platformEnabled {
                        Button("开启平台") {
                            Task {
                                await store.enableWebhookPlatform(
                                    session: session
                                )
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Spacer()
                    if !page.baseURL.isEmpty {
                        Text(page.baseURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HubSectionHeader(
                    title: "订阅", count: page.subscriptions.count
                )
                ForEach(page.subscriptions) { route in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(.callout.weight(.medium))
                            Text([
                                route.url,
                                route.events.joined(separator: ", "),
                                route.secretSet ? "密钥已设" : "无密钥",
                            ].joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { route.enabled },
                            set: { newValue in
                                Task {
                                    await store.setWebhookEnabled(
                                        session: session,
                                        name: route.name,
                                        enabled: newValue
                                    )
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        Button("删除") { confirmDelete = route.name }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "Webhooks 暂不可用。")
            }
            HubSectionHeader(title: "新建订阅")
            TextField("名称", text: $newName)
                .textFieldStyle(.roundedBorder)
            TextField("URL", text: $newURL)
                .textFieldStyle(.roundedBorder)
            TextField("事件（逗号分隔，可空）", text: $newEvents)
                .textFieldStyle(.roundedBorder)
            if let secret = oneTimeSecret {
                Text("一次性密钥（只显示这一次，请立即保存）：\(secret)")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("新建") { Task { await create() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty || newURL.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个 Webhook 订阅？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let name = confirmDelete {
                    Task {
                        await store.deleteWebhook(
                            session: session, name: name
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }

    private func create() async {
        guard let config = session.config, let key = session.apiKey
        else { return }
        var body: [String: JSONValue] = [
            "name": .string(newName),
            "url": .string(newURL),
        ]
        let events = newEvents
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !events.isEmpty {
            body["events"] = .array(events.map { .string($0) })
        }
        do {
            let receipt = try await session.chatClient
                .hubCreateWebhook(
                    config: config, apiKey: key, body: body
                )
            oneTimeSecret = receipt.hubFirstStr(
                ["secret", "webhook_secret", "token"]
            )
            store.actionNote = "订阅已新建（已回读）"
            newName = ""
            newURL = ""
            newEvents = ""
            await store.load(.webhooks, session: session, force: true)
        } catch let error as HermesError {
            store.actionNote = error.userMessage
        } catch {
            store.actionNote = "新建 Webhook 失败"
        }
    }
}
