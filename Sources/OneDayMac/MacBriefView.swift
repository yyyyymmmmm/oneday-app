import SwiftUI
import OneDayCore

/// 动态简报（棒 3，对位 #34）：当前生效全文查看/编
/// 辑——保存走 PUT /meta/brief（单层 text 口径），回
/// 执全文替换；润色状态如实呈现（polished/状态原文
/// 只展示、不猜译）。
struct MacBriefView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    var store: MacFeedStore
    @State private var draft: String = ""
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("动态简报")
                    .font(.headline)
                Spacer()
                if let brief = store.brief {
                    Text(
                        brief.polished
                            ? "当前为润色稿" : "当前为原文"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Text("简报决定晨报与调研的方向。保存后服务端按新全文起润色/调研。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 260)
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
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    saving = true
                    Task {
                        let ok = await store.saveBrief(
                            session: session, text: draft
                        )
                        saving = false
                        if ok { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saving)
            }
        }
        .padding(18)
        .frame(width: 560)
        .onAppear {
            draft = store.brief?.text ?? ""
        }
    }
}
