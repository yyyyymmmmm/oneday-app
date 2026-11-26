import SwiftUI
import OneDayCore

/// 目标表单（棒 3，对位 #36）：新建/编辑共用一张
/// Sheet（macOS 原生形态，与拟案「新建/编辑走 Sheet
/// 窗」一致）；新建可带父目标（子目标）。保存口径走
/// Core 工厂（去首尾空白、空备注不带字段）。
struct MacGoalFormView: View {
    @Environment(SessionStore.self) private var session
    var store: MacGoalsStore
    /// 编辑对象；nil＝新建
    let goal: BridgeGoal?
    /// 新建时的父目标（子目标创建）
    let parentId: String?
    var onDone: () -> Void

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var saving = false

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(goal == nil ? "新建目标" : "编辑目标")
                .font(.headline)
            if goal == nil, parentId != nil {
                Text("作为子目标创建")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
            Text("备注（可选）")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $note)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )
            if let note = store.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { onDone() }
                    .keyboardShortcut(.cancelAction)
                Button(goal == nil ? "新建" : "保存") {
                    saving = true
                    Task {
                        await save()
                        saving = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || saving)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear {
            if let goal {
                title = goal.title
                note = goal.note
            }
        }
    }

    private func save() async {
        if let goal {
            await store.patch(
                session: session, goal: goal,
                title: title, note: note
            )
            onDone()
        } else if await store.create(
            session: session, title: title, note: note,
            parentId: parentId
        ) != nil {
            onDone()
        }
    }
}
