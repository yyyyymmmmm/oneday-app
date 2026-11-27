import OneDayCore
import OneDayDesign
import SwiftUI

struct MailApprovalCard: View {
    let approval: MailSendApproval
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Palette.brandPrimary)
                Text("邮件发送请求")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(approval.timestamp, style: .time)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                metadataRow("收件人", approval.to)
                metadataRow("主题", approval.subject.isEmpty ? "（无主题）" : approval.subject)

                if !approval.bodyPreview.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("正文预览")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                        Text(approval.bodyPreview)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(3)
                    }
                }
            }
            .padding(.vertical, OneDayMetrics.spacingXS)

            HStack(spacing: OneDayMetrics.spacingSM) {
                Button {
                    onApprove()
                } label: {
                    Text("批准发送")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onReject()
                } label: {
                    Text("驳回")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(OneDayMetrics.spacingM)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.brandPrimary.opacity(0.3), lineWidth: 1)
        )
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
        }
    }
}
