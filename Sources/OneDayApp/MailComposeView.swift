import OneDayCore
import OneDayDesign
import SwiftUI

struct MailComposeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    private let client = HermesClient()

    @State private var to: String
    @State private var subject: String
    @State private var body: String
    @State private var saving = false
    @State private var errorMessage: String?

    /// 编辑现有草稿时传入（服务端 2.20.0 无 PUT /v1/mail/drafts/{id} 更新端点，
    /// 存草稿会创建新草稿、旧草稿保留，用户需手动删除旧草稿——限制已在交卷明标）
    let existingDraft: MailDraft?

    init(to: String = "", subject: String = "", body: String = "", draft: MailDraft? = nil) {
        self.existingDraft = draft
        self._to = State(initialValue: draft?.to ?? to)
        self._subject = State(initialValue: draft?.subject ?? subject)
        self._body = State(initialValue: draft?.bodyText ?? body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("收件人", text: $to)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                    TextField("主题", text: $subject)
                } header: {
                    Text("邮件信息")
                }

                Section {
                    TextEditor(text: $body)
                        .frame(minHeight: 200)
                } header: {
                    Text("正文")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingDraft == nil ? "写信" : "编辑草稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("存草稿") { Task { await saveDraft() } }
                        .disabled(to.isEmpty || saving)
                }
            }
            .disabled(saving)
        }
    }

    @MainActor
    private func saveDraft() async {
        guard let config = appState.config,
              let apiKey = await appState.effectiveBearerToken() else {
            errorMessage = "服务器连接凭据不可用。"
            return
        }

        guard !to.isEmpty else {
            errorMessage = "收件人不能为空。"
            return
        }

        saving = true
        errorMessage = nil

        do {
            let request = CreateDraftRequest(
                to: to.trimmingCharacters(in: .whitespacesAndNewlines),
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                bodyText: body
            )
            _ = try await client.createMailDraft(
                config: config, apiKey: apiKey, request: request
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            saving = false
        }
    }
}
