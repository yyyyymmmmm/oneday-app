import OneDayCore
import OneDayDesign
import SwiftUI

struct MailDraftsView: View {
    @Environment(AppState.self) private var appState
    private let client = HermesClient()

    @State private var drafts: [MailDraft] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var showingCompose = false
    @State private var editingDraft: MailDraft?
    @State private var pendingApproval: MailSendApproval?
    @State private var sendingDraftID: String?
    @State private var sendError: String?

    var body: some View {
        ZStack(alignment: .top) {
            mainContent
            if let approval = pendingApproval {
                approvalOverlay(approval)
            }
        }
        .navigationTitle("草稿")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingCompose) {
            MailComposeView()
                .onDisappear { load() }
        }
        .sheet(item: $editingDraft) { draft in
            MailComposeView(draft: draft)
                .onDisappear { load() }
        }
        .task { await loadDrafts() }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if loading && drafts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, drafts.isEmpty {
                ContentUnavailableView {
                    Label("草稿无法读取", systemImage: "envelope.badge")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试", action: load)
                }
            } else if drafts.isEmpty {
                ContentUnavailableView(
                    "暂无草稿",
                    systemImage: "tray",
                    description: Text("点击右上角新建草稿。")
                )
            } else {
                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    if let sendError {
                        Text("发送失败：\(sendError)")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    ForEach(drafts) { draft in
                        draftRow(draft)
                    }
                }
                .listStyle(.plain)
                .refreshable { await loadDrafts() }
            }
        }
    }

    @ViewBuilder
    private func approvalOverlay(_ approval: MailSendApproval) -> some View {
        VStack {
            MailApprovalCard(
                approval: approval,
                onApprove: { Task { await approveSend(approval) } },
                onReject: { rejectSend() }
            )
            .padding(OneDayMetrics.spacingM)
            .shadow(radius: 8)
            Spacer()
        }
        .background(Color.black.opacity(0.3))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: pendingApproval != nil)
    }

    private func draftRow(_ draft: MailDraft) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
            HStack(alignment: .firstTextBaseline, spacing: OneDayMetrics.spacingSM) {
                Text(draft.to)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if draft.status == "sent" {
                    Text("已发送")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if draft.status == "sending" {
                    Text("发送中")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(Date(timeIntervalSince1970: TimeInterval(draft.updatedAt)), style: .date)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            Text(draft.subject.isEmpty ? "（无主题）" : draft.subject)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(draft.bodyText)
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)

            if let sendError = draft.sendError {
                Text("发送失败：\(sendError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if draft.status == "draft" {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    Button("发送") {
                        requestSendApproval(draft)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(sendingDraftID != nil)

                    Button("编辑") {
                        editingDraft = draft
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, OneDayMetrics.spacingXS)
            }
        }
        .padding(.vertical, OneDayMetrics.spacingXS)
    }

    private func load() {
        Task { await loadDrafts() }
    }

    @MainActor
    private func loadDrafts() async {
        guard let config = appState.config,
              let apiKey = await appState.effectiveBearerToken() else {
            errorMessage = "服务器连接凭据不可用。"
            loading = false
            return
        }

        loading = true
        errorMessage = nil

        do {
            let response = try await client.mailDrafts(config: config, apiKey: apiKey)
            drafts = response.data.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }

        loading = false
    }

    @MainActor
    private func requestSendApproval(_ draft: MailDraft) {
        sendError = nil
        pendingApproval = MailSendApproval(
            draftID: draft.id,
            to: draft.to,
            subject: draft.subject,
            bodyPreview: String(draft.bodyText.prefix(200))
        )
    }

    @MainActor
    private func approveSend(_ approval: MailSendApproval) async {
        guard let config = appState.config,
              let apiKey = await appState.effectiveBearerToken() else {
            sendError = "服务器连接凭据不可用。"
            pendingApproval = nil
            return
        }

        sendingDraftID = approval.draftID
        pendingApproval = nil
        sendError = nil

        do {
            let approvalRef = "mail-\(approval.draftID)-\(Int(Date().timeIntervalSince1970))"
            let request = SendDraftRequest(approvalRef: approvalRef)
            try await client.sendMailDraft(
                config: config, apiKey: apiKey, draftID: approval.draftID, request: request
            )
            await loadDrafts()
        } catch {
            sendError = error.localizedDescription
        }

        sendingDraftID = nil
    }

    private func rejectSend() {
        pendingApproval = nil
        sendError = nil
    }
}

struct MailSendApproval: Identifiable, Sendable {
    let id = UUID()
    let draftID: String
    let to: String
    let subject: String
    let bodyPreview: String
    let timestamp = Date()
}
