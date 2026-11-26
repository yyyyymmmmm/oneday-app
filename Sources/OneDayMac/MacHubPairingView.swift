import SwiftUI
import OneDayCore

/// 配对管理面（棒 4，对位 #62）：待批配对（批准/
/// 清空）＋已配对（撤销），走面板 /api/pairing 系
/// （cookie 随共享会话自动带上，与 iOS 同路），
/// 动作后回读清单对账
struct MacHubPairingView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmRevoke: (platform: String, userID: String)?
    @State private var confirmClear = false

    private var pending: [JSONValue] {
        store.pairing?.hubFirstList(
            ["pending", "pending_requests"]
        ) ?? []
    }

    private var paired: [JSONValue] {
        store.pairing?.hubFirstList(
            ["paired", "approved", "users"]
        ) ?? []
    }

    var body: some View {
        HubScroll {
            HStack(spacing: 8) {
                HubSectionHeader(
                    title: "待批配对", count: pending.count
                )
                Spacer()
                if !pending.isEmpty {
                    Button("清空待批") { confirmClear = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
            }
            if pending.isEmpty {
                HubEmptyText(text: "暂无待批配对。")
            }
            ForEach(Array(pending.enumerated()), id: \.offset) { _, row in
                let platform = row.hubFirstStr(
                    ["platform", "channel"]
                ) ?? ""
                let requestID = row.hubFirstStr(
                    ["request_id", "id"]
                ) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.hubFirstStr(
                            ["user_name", "name", "user_id"]
                        ) ?? requestID)
                            .font(.callout.weight(.medium))
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("批准") {
                        Task {
                            await store.pairingApprove(
                                session: session,
                                platform: platform,
                                requestID: requestID
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                }
                Divider()
            }
            HubSectionHeader(title: "已配对", count: paired.count)
            if paired.isEmpty {
                HubEmptyText(text: "暂无已配对用户。")
            }
            ForEach(Array(paired.enumerated()), id: \.offset) { _, row in
                let platform = row.hubFirstStr(
                    ["platform", "channel"]
                ) ?? ""
                let userID = row.hubFirstStr(
                    ["user_id", "id"]
                ) ?? ""
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.hubFirstStr(
                            ["user_name", "name"]
                        ) ?? userID)
                            .font(.callout.weight(.medium))
                        Text(platform)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("撤销") {
                        confirmRevoke = (platform, userID)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Divider()
            }
        }
        .confirmationDialog(
            "撤销这条配对？",
            isPresented: Binding(
                get: { confirmRevoke != nil },
                set: { if !$0 { confirmRevoke = nil } }
            )
        ) {
            Button("撤销", role: .destructive) {
                if let target = confirmRevoke {
                    Task {
                        await store.pairingRevoke(
                            session: session,
                            platform: target.platform,
                            userID: target.userID
                        )
                    }
                }
                confirmRevoke = nil
            }
            Button("取消", role: .cancel) { confirmRevoke = nil }
        }
        .confirmationDialog(
            "清空全部待批配对？",
            isPresented: $confirmClear
        ) {
            Button("清空", role: .destructive) {
                Task {
                    await store.pairingClearPending(session: session)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
}
