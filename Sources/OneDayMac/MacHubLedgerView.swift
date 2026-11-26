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
