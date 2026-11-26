import SwiftUI
import OneDayCore
import OneDayDesign

/// 写闸待批卡（棒 2，对位 #18）：卡面文案与动作栈
/// 全部消费 Core 单源——标题问句/说明行/后果句走
/// ApprovalCardCopy，钮集与次序走 ApprovalCardSpec
/// （批准主钮／总是允许这一类次钮／驳回文字级；
/// 防呆死单只留驳回、高风险不给总是允许），与 iOS
/// 聊天卡、枢纽卡同一张脸，不许 Mac 另拼一套。
struct MacWriteGateCardView: View {
    @Environment(SessionStore.self) private var session
    let record: WriteGateRecord
    let note: String?
    let isDeciding: Bool
    let onApprove: () -> Void
    let onAlways: () -> Void
    let onReject: () -> Void

    @State private var detail: WriteGateDetail?
    @State private var detailLoading = false
    @State private var detailError: String?
    @State private var detailShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(ApprovalCardCopy.summaryLine(for: record))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(ApprovalCardCopy.consequence(for: record))
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let line = ApprovalCardCopy.reasonLine(for: record) {
                Label(line, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if detailShown { detailBlock }
            actionRow
        }
        .padding(12)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(
                systemName: ApprovalCardSpec.toolIconName(
                    for: record.subsystem
                )
            )
            .foregroundStyle(.secondary)
            Text(ApprovalCardCopy.question(for: record))
                .font(.headline)
                .lineLimit(2)
            Spacer()
            Text(record.subsystem.badgeLabel)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Palette.primary.opacity(0.12), in: Capsule()
                )
            if let created = record.createdAt {
                Text(created, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 改动对照（详情按需拉取）

    @ViewBuilder
    private var detailBlock: some View {
        if detailLoading {
            ProgressView().controlSize(.small)
        } else if let detail {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(
                    Array(detail.review.noteLabels.enumerated()),
                    id: \.offset
                ) { _, label in
                    Label(label, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let old = detail.review.requestedOldString,
                   !old.isEmpty {
                    Text("定位文本已不存在，批准前请仔细核对改动。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ScrollView {
                    Text(detail.review.displayDiff)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity, alignment: .leading
                        )
                }
                .frame(maxHeight: 180)
                .padding(8)
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
        } else if let detailError {
            Text(detailError)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func toggleDetail() {
        detailShown.toggle()
        guard detailShown, detail == nil, !detailLoading else { return }
        detailLoading = true
        detailError = nil
        Task {
            defer { detailLoading = false }
            guard let config = session.config,
                  let key = session.apiKey else { return }
            do {
                detail = try await session.chatClient.writeGateDetail(
                    config: config, apiKey: key,
                    subsystem: record.subsystem, id: record.id
                )
            } catch let error as MacWriteGateError {
                detailError = error.userMessage
            } catch {
                detailError = "改动对照加载失败"
            }
        }
    }

    // MARK: - 动作栈（Core 派生，视图层不自拼）

    private var actions: [ApprovalCardAction] {
        ApprovalCardSpec.actionStack(
            canDecide: record.canDecide,
            blocked: record.isBlocked,
            highRisk: record.isHighRisk
        )
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .approve:
                    Button(action.title()) { onApprove() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDeciding)
                case .alwaysAllow:
                    Button(action.title()) { onAlways() }
                        .buttonStyle(.bordered)
                        .disabled(isDeciding)
                case .reject:
                    Button(action.title(), role: .destructive) {
                        onReject()
                    }
                    .buttonStyle(.borderless)
                    .disabled(isDeciding)
                }
            }
            if isDeciding {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button(detailShown ? "收起改动" : "查看改动") {
                toggleDetail()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }
}
