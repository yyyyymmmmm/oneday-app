import OneDayDesign
import OneDayCore
import SwiftUI

/// 环境变量编辑表单：新增（键＋值）与改值（键锁定）共用。
/// 值默认按密钥处理走 SecureField 不回显。
struct EnvVarEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let existingKey: String?
    var onSaved: () -> Void = {}

    @State private var key: String
    @State private var value: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(existingKey: String?, onSaved: @escaping () -> Void = {}) {
        self.existingKey = existingKey
        self.onSaved = onSaved
        _key = State(initialValue: existingKey ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 0) {
                        FieldRow(label: "键") {
                            TextField("如 DEEPSEEK_API_KEY", text: $key)
                                .font(.system(.body, design: .monospaced))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .disabled(existingKey != nil)
                        }
                        GroupDivider()
                        FieldRow(label: "值") {
                            SecureField("输入新值", text: $value)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .odGroup()
                    if let errorMessage {
                        InlineError(errorMessage)
                            .padding(.top, OneDayMetrics.spacingM)
                    }
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
            }
            .background(Palette.pageBG)
            .navigationTitle(existingKey == nil ? "新增环境变量" : "修改值")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(
                        key.trimmingCharacters(in: .whitespaces).isEmpty
                            || value.isEmpty || isSaving
                    )
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.performAdmin { client, config in
                try await client.setEnvVar(
                    config: config,
                    key: key.trimmingCharacters(in: .whitespaces),
                    value: value
                )
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "保存失败，请稍后再试。"
        }
    }
}
