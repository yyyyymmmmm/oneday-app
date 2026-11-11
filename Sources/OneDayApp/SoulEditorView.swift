import OneDayCore
import OneDayDesign
import SwiftUI

/// 人设编辑面（§154 HUB-1，规格 §2.7 六环链的编辑环）：
/// 从枢纽身份段的编辑钮进入。初值＝服务器取回的人设
/// 全文（对全文下手，不拿解析后的段落拼回——解析有
/// 损）；保存走 AgentHubStore.saveSoul：写入后重新取
/// 回比对一致才报「已保存」，没确认/档案已切换都明示
/// 且草稿保留在本面不丢。
struct SoulEditorView: View {
    let store: AgentHubStore

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var phase: Phase = .editing

    private enum Phase: Equatable {
        case editing
        case saving
        case saved
        case unconfirmed
        case profileChanged
        case notReady
    }

    init(store: AgentHubStore) {
        self.store = store
        _draft = State(initialValue: store.soulDocument?.content ?? "")
    }

    private var original: String { store.soulDocument?.content ?? "" }
    private var hasChanges: Bool { draft != original }
    private var isSaving: Bool { phase == .saving }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                if let name = store.frozenProfileName {
                    Text("当前档案：\(name)")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                }
                Text("改的是智能体的人设，会保存在服务器上。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }

            TextEditor(text: $draft)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .disabled(isSaving)
                .accessibilityLabel("人设全文")

            statusLine
        }
        .padding(OneDayMetrics.pageGutter)
        .background(Palette.pageBG)
        .navigationTitle("编辑人设")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(isSaving || !hasChanges)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .editing:
            EmptyView()
        case .saving:
            HStack(spacing: OneDayMetrics.spacingS) {
                ProgressView()
                Text("正在保存…")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        case .saved:
            Label("已保存", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Palette.success)
        case .unconfirmed:
            Label(
                "没能确认保存成功，你写的内容还在这里，请再试一次。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(Palette.danger)
        case .profileChanged:
            Label(
                "档案已经切换了，这次没有保存。回到身份段确认是哪一份档案后再改。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(Palette.danger)
        case .notReady:
            Label(
                "人设内容还没读到，请返回身份段重新打开。",
                systemImage: "exclamationmark.triangle"
            )
            .font(.footnote)
            .foregroundStyle(Palette.danger)
        }
    }

    private func save() async {
        phase = .saving
        switch await store.saveSoul(content: draft) {
        case .confirmed:
            phase = .saved
            // 成功停留一拍让用户看见，再返回身份段（段
            // 内呈现已由 store 同步刷新）
            try? await Task.sleep(for: .milliseconds(900))
            dismiss()
        case .unconfirmed:
            phase = .unconfirmed
        case .profileChanged:
            phase = .profileChanged
        case .notReady:
            phase = .notReady
        }
    }
}
