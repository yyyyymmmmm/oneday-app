import SwiftUI
import OneDayCore
import OneDayDesign

/// 授权管理（棒 2，对位 #19）：两件——统一授权清
/// 单（/v1/grants：命令授权可在此撤销、写闸授权只
/// 读呈现）＋「总是允许」规则（/v1/write-gate/rules
/// 可查可撤销）。口径与 iOS 授权节逐字同：查不到
/// 的时间/来源显「未记录」不编造；partial 时如实说
/// 没读全；撤销成败以事后清单回读为准（店内已办）。
struct MacGrantsView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var store: MacApprovalStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                rulesSection
                Divider()
                grantsSection
            }
            .padding(14)
        }
        .task {
            await store.refreshRules(session: session)
            await store.refreshGrants(session: session)
        }
    }

    // MARK: - 「总是允许」规则

    @ViewBuilder
    private var rulesSection: some View {
        Text("「总是允许」规则")
            .font(.headline)
        Text("在待批卡上点「总是允许这一类」，同类写入以后直接通过、不再逐条问；撤销一条，恢复逐条审批。")
            .font(.caption)
            .foregroundStyle(.secondary)
        if let note = store.rulesNote {
            Text(note)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if store.rules.isEmpty {
            Text(
                store.rulesLoaded
                    ? "暂无规则。"
                    : "规则读取中…"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        } else {
            ForEach(store.rules) { rule in
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.scopeLabel)
                            .font(.callout)
                        if let created = rule.createdAt {
                            Text(
                                "立于 \(created.formatted(date: .abbreviated, time: .shortened))"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("撤销") {
                        Task {
                            await store.revokeRule(
                                rule, session: session
                            )
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.revokingIDs.contains(rule.id))
                }
                .padding(10)
                .background(
                    Palette.surface,
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
        }
    }

    // MARK: - 统一授权清单

    @ViewBuilder
    private var grantsSection: some View {
        Text("常设授权")
            .font(.headline)
        if let note = store.grantsNote {
            Text(note)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if let grants = store.grants {
            if grants.partial {
                Label(
                    "清单没读全（\(grants.sourceErrors.joined(separator: "、"))），下面只是读到的部分。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            if grants.grants.isEmpty {
                Text("暂无常设授权。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(grants.grants) { entry in
                    grantRow(entry)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取授权清单…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func grantRow(_ entry: GrantEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(
                systemName: entry.source == .exec
                    ? "terminal" : "pencil.and.list.clipboard"
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.scopeLabel)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(entry.source == .exec ? "命令授权" : "写入授权")
                    Text(
                        "· 立于 \(entry.grantedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "未记录")"
                    )
                    Text(entry.expiresAt == nil ? "· 永久" : "· 有期限")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !entry.canRevokeHere {
                    Text("写闸授权在上面的规则区撤销。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if entry.canRevokeHere {
                Button("撤销") {
                    Task {
                        await store.revokeGrant(
                            entry, session: session
                        )
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.revokingIDs.contains(entry.grantKey))
            }
        }
        .padding(10)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 10)
        )
    }
}
