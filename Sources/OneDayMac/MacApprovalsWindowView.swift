import SwiftUI
import OneDayCore
import OneDayDesign

/// 批准面独立窗（棒 2，对位 #18/#19）：待批全量
/// （两族逐条可裁决）、已决回看、授权管理三段。
/// 从菜单栏小面板与聊天停靠区「全部待批」打开；
/// 窗内裁决与聊天卡共用同一状态店与同一语义。
struct MacApprovalsWindowView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var store: MacApprovalStore
    @State private var segment = Segment.pending

    enum Segment: String, CaseIterable {
        case pending = "待批"
        case decided = "已决"
        case grants = "授权"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)
            Divider()
            switch segment {
            case .pending:
                pendingList
            case .decided:
                decidedList
            case .grants:
                MacGrantsView(store: store)
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            await store.refresh(session: session)
        }
    }

    // MARK: - 待批

    @ViewBuilder
    private var pendingList: some View {
        let gate = store.gatePending
        let exec = store.execPending
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let note = store.execNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                gateSection(records: gate)
                if !exec.isEmpty {
                    sectionTitle("命令执行（\(exec.count)）")
                    ForEach(exec) { record in
                        MacExecApprovalCardView(
                            record: record,
                            isDeciding: store.decidingIDs
                                .contains(record.id),
                            onDecide: { choice in
                                Task {
                                    await store.decideExec(
                                        record, choice: choice,
                                        session: session
                                    )
                                }
                            }
                        )
                    }
                }
                if gate.isEmpty && exec.isEmpty {
                    ContentUnavailableView(
                        "没有待批事项",
                        systemImage: "checkmark.shield",
                        description: Text("新的待批会出现在这里。")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(14)
        }
    }

    /// 写闸段按诚实三态呈现：未接通/未启用不冒充无待批
    @ViewBuilder
    private func gateSection(
        records: [WriteGateRecord]
    ) -> some View {
        switch store.gateState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取写入审批…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .bridgeUnavailable:
            Label(
                "写入审批通道未接通，暂时读不到待批。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
        case .gateDisabled:
            Label(
                "写入审批还没启用，现在没有待批。",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red)
        case .ready:
            if !records.isEmpty {
                sectionTitle("写入审批（\(records.count)）")
                ForEach(records) { record in
                    MacWriteGateCardView(
                        record: record,
                        note: store.cardNotes[record.id],
                        isDeciding: store.decidingIDs.contains(record.id),
                        onApprove: {
                            Task {
                                await store.decideGate(
                                    record, approve: true,
                                    session: session
                                )
                            }
                        },
                        onAlways: {
                            Task {
                                await store.decideAlways(
                                    record, session: session
                                )
                            }
                        },
                        onReject: {
                            Task {
                                await store.decideGate(
                                    record, approve: false,
                                    session: session
                                )
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - 已决

    private var decidedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !store.decisions.isEmpty {
                    sectionTitle("写入审批已决")
                    ForEach(store.decisions, id: \.id) { record in
                        decidedGateRow(record)
                    }
                }
                if !store.execDecided.isEmpty {
                    sectionTitle("命令执行已决")
                    ForEach(store.execDecided) { record in
                        MacExecApprovalCardView(
                            record: record,
                            isDeciding: false,
                            onDecide: { _ in }
                        )
                    }
                }
                if store.decisions.isEmpty && store.execDecided.isEmpty {
                    ContentUnavailableView(
                        "还没有已决记录",
                        systemImage: "clock",
                        description: Text("批准或驳回后会留在这里。")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(14)
        }
    }

    private func decidedGateRow(
        _ record: WriteGateDecisionRecord
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(
                systemName: record.decision == "approved"
                    ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .foregroundStyle(
                record.decision == "approved" ? .green : .red
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(record.headline)
                    .font(.callout)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(record.decisionLabel)
                    if record.isRuleApproved {
                        Text("· 经「总是允许」规则")
                    }
                    if let preview = record.contentPreview,
                       !preview.isEmpty,
                       !record.headline.contains(preview) {
                        Text("· \(preview)").lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let decided = record.decidedAt {
                Text(decided, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 2)
    }
}
