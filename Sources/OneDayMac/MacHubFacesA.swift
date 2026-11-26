import SwiftUI
import OneDayCore

/// 工作台账面（棒 4，对位 #39）：汇总＋条目列＋条
/// 目详情，数据全走桥 /ledger 三口，只读呈现（写口
/// 在各业务面，台账是聚合账面，与 iOS 同口径）
struct MacHubLedgerView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var selectedID: String?

    var body: some View {
        HubScroll {
            if let summary = store.ledgerSummary {
                HubSectionHeader(title: "汇总")
                HubJSONSummaryView(value: summary)
            }
            HubSectionHeader(
                title: "条目", count: store.ledgerEntries.count
            )
            if store.ledgerEntries.isEmpty {
                HubEmptyText(text: "台账暂无条目。")
            }
            ForEach(
                Array(store.ledgerEntries.enumerated()),
                id: \.offset
            ) { _, entry in
                let id = entry.hubFirstStr(["id", "entry_id"]) ?? ""
                Button {
                    selectedID = id
                    Task {
                        await store.loadLedgerEntry(
                            session: session, id: id
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.hubFirstStr(
                                ["title", "name", "summary"]
                            ) ?? "（无标题）")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(entry.hubFirstStr(
                                ["status", "kind", "created_at"]
                            ) ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedID == id {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if selectedID == id, let detail = store.ledgerDetail {
                    HubJSONSummaryView(value: detail)
                        .padding(.leading, 12)
                }
                Divider()
            }
        }
    }
}

/// 审计面（棒 4，对位 #40）：已决记录＋「总是允许」
/// 规则＋统一授权三段，状态与撤销动作全归棒 2 既有
/// MacApprovalStore（同一份状态，不另立第二份）；
/// 本面是它在枢纽内的落点
struct MacHubAuditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(MacApprovalStore.self) private var approvals

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "已决记录", count: approvals.decisions.count
            )
            if approvals.decisions.isEmpty {
                HubEmptyText(text: "暂无已决记录。")
            }
            ForEach(approvals.decisions) { record in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: record.decision == "approved"
                        || record.decision == "approve"
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill")
                        .foregroundStyle(record.decision == "approved"
                            || record.decision == "approve"
                            ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.summary)
                            .font(.callout.weight(.medium))
                        Text([
                            record.origin,
                            record.decidedAt.map {
                                $0.formatted(
                                    date: .abbreviated,
                                    time: .shortened
                                )
                            } ?? "未记录",
                            record.viaRule.map { "经规则 \($0)" },
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
            }

            HubSectionHeader(
                title: "总是允许规则", count: approvals.rules.count
            )
            if let note = approvals.rulesNote {
                Text(note).font(.callout).foregroundStyle(.orange)
            }
            if approvals.rules.isEmpty {
                HubEmptyText(text: "暂无规则。在批准卡上点「总是允许」即立一条。")
            }
            ForEach(approvals.rules) { rule in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.originLabel)
                            .font(.callout.weight(.medium))
                        Text(rule.scopeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("撤销") {
                        Task {
                            await approvals.revokeRule(
                                rule, session: session
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Divider()
            }

            HubSectionHeader(
                title: "统一授权",
                count: approvals.grants?.grants.count
            )
            if let note = approvals.grantsNote {
                Text(note).font(.callout).foregroundStyle(.orange)
            }
            if let grants = approvals.grants {
                if grants.partial {
                    Text("清单不完整（部分来源读取失败），如实呈现已读到的部分。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(grants.grants) { entry in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.scopeLabel)
                                .font(.callout.weight(.medium))
                            Text([
                                entry.status,
                                entry.grantedAt.map {
                                    "立于 \($0.formatted(date: .abbreviated, time: .shortened))"
                                } ?? "未记录",
                            ].joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entry.canRevokeHere {
                            Button("撤销") {
                                Task {
                                    await approvals.revokeGrant(
                                        entry, session: session
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                    Divider()
                }
            } else {
                HubEmptyText(text: "授权清单读取中或暂不可用。")
            }
        }
        .task {
            await approvals.refreshGate(session: session)
            await approvals.refreshRules(session: session)
            await approvals.refreshGrants(session: session)
        }
    }
}

/// 电脑面（棒 4，对位 #41）：电脑操控状态＋出口状
/// 态两段状态呈现（与 iOS 电脑面同源两口）；桌面/
/// 文件/终端的操控动作在 iOS 走盒桥交互面，Mac 本
/// 棒只落状态总览，操控面归后续（见销账段明示）
struct MacHubComputerView: View {
    let store: MacHubStore

    var body: some View {
        HubScroll {
            HubSectionHeader(title: "电脑操控状态")
            if let status = store.computerStatus {
                HubJSONSummaryView(value: status)
            } else {
                HubEmptyText(text: "电脑状态暂不可用。")
            }
            HubSectionHeader(title: "出口状态")
            if let egress = store.egressStatus {
                HubJSONSummaryView(value: egress)
            } else {
                HubEmptyText(text: "出口状态暂不可用。")
            }
        }
    }
}

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
            systemImage: "envelope.badge.slash",
            description: Text(
                "服务端还没有邮件数据源，iOS 端此面同样不可达。本面不摆假数据，数据源长出后同步接入。"
            )
        )
    }
}
