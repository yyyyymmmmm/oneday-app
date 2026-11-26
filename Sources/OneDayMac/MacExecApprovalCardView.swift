import SwiftUI
import OneDayCore
import OneDayDesign

/// 执行批准卡（棒 2，对位 #18）：智能体要执行命令
/// 时的待批——命令与说明上卡，裁决钮只渲染服务端
/// 随记录给的 choices（批准/本次会话内总是允许/
/// 总是允许/拒绝），端侧不自造档位。无活等待者的
/// 投影记录只看不批（answerable=false），如实标注。
struct MacExecApprovalCardView: View {
    let record: MacExecApproval
    let isDeciding: Bool
    let onDecide: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !record.description.isEmpty {
                Text(record.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if !record.command.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(record.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            if !record.patternKeys.isEmpty {
                Text("涉及：\(record.patternKeys.joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            footer
        }
        .padding(12)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text("允许智能体执行这条命令？")
                .font(.headline)
                .lineLimit(2)
            Spacer()
            if let created = record.createdDate {
                Text(created, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if record.isPending {
            if record.answerable {
                HStack(spacing: 10) {
                    ForEach(record.choices, id: \.self) { choice in
                        if let title = MacApprovalChoiceCopy.title(
                            for: choice
                        ) {
                            choiceButton(choice: choice, title: title)
                        }
                    }
                    if isDeciding {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
            } else {
                Label(
                    "这条批准没有正在等待的执行，只能查看。",
                    systemImage: "eye"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        } else {
            Label(
                MacApprovalChoiceCopy.decidedLabel(for: record),
                systemImage: "checkmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func choiceButton(
        choice: String, title: String
    ) -> some View {
        switch choice {
        case "once":
            Button(title) { onDecide(choice) }
                .buttonStyle(.borderedProminent)
                .disabled(isDeciding)
        case "deny":
            Button(title, role: .destructive) { onDecide(choice) }
                .buttonStyle(.borderless)
                .disabled(isDeciding)
        default:
            Button(title) { onDecide(choice) }
                .buttonStyle(.bordered)
                .disabled(isDeciding)
        }
    }
}
