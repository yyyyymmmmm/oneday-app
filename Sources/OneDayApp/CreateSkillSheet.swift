import OneDayCore
import OneDayDesign
import SwiftUI

/// 新建技能表单（Hermes v0.23.0 `POST /api/skills`）
struct CreateSkillSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onCreated: () -> Void

    @State private var name = ""
    @State private var category = ""
    @State private var content = """
    ---
    name: my-skill
    description: 简述该技能的适用场景与核心步骤
    ---

    # 使用说明

    1. 第一步：
    2. 第二步：
    """
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("技能名称（如 daily-review）", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("分类（可选，如 productivity）", text: $category)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("技能定义（SKILL.md）") {
                    TextEditor(text: $content)
                        .font(.metaMonospaced)
                        .frame(minHeight: 240)
                }

                if let errorMessage {
                    Section {
                        InlineError(errorMessage)
                    }
                }
            }
            .navigationTitle("新建技能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "创建中…" : "创建") {
                        Task { await submit() }
                    }
                    .disabled(trimmedName.isEmpty || trimmedContent.isEmpty || isSaving)
                }
            }
        }
        .fullscreenPopBridge()
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let trimmedCat = category.trimmingCharacters(in: .whitespacesAndNewlines)
            try await appState.performAdmin { client, config in
                try await client.createSkill(
                    config: config,
                    name: trimmedName,
                    content: content,
                    category: trimmedCat.isEmpty ? nil : trimmedCat
                )
            }
            onCreated()
            dismiss()
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "创建技能失败，请检查名称与内容。"
        }
    }
}
