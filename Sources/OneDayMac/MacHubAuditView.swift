import SwiftUI
import OneDayCore

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
