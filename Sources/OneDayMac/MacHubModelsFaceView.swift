import SwiftUI
import OneDayCore

/// 模型与服务商面（棒 4，对位 #63）：可选模型清单
/// ＋设主模型＋辅助模型/MoA 配置呈现（/api/model
/// 系既有口，与 iOS 模型面同源）
struct MacHubModelsFaceView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var confirmModel: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "可选模型", count: store.modelOptions.count
            )
            if store.modelOptions.isEmpty {
                HubEmptyText(text: "模型清单暂不可用。")
            }
            ForEach(store.modelOptions, id: \.self) { model in
                HStack(spacing: 8) {
                    Text(model)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Button("设为主模型") { confirmModel = model }
                        .buttonStyle(.borderless)
                }
                Divider()
            }
            if let auxiliary = store.auxiliary {
                HubSectionHeader(title: "辅助模型")
                HubJSONSummaryView(value: auxiliary)
            }
            if let moa = store.moa {
                HubSectionHeader(title: "MoA 配置")
                HubJSONSummaryView(value: moa)
            }
        }
        .confirmationDialog(
            "把主模型设为所选模型？",
            isPresented: Binding(
                get: { confirmModel != nil },
                set: { if !$0 { confirmModel = nil } }
            )
        ) {
            Button("设置") {
                if let model = confirmModel {
                    Task {
                        await store.setMainModel(
                            session: session, model: model
                        )
                    }
                }
                confirmModel = nil
            }
            Button("取消", role: .cancel) { confirmModel = nil }
        }
    }
}
