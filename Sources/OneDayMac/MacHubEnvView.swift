import SwiftUI
import OneDayCore

/// 环境变量面（棒 4，对位 #57）：清单只显遮蔽值与
/// 是否已设；明文只在点「查看」时经 reveal 口当次
/// 取回呈现、不落盘；设值/删除后回读
struct MacHubEnvView: View {
    @Environment(SessionStore.self) private var session
    let store: MacHubStore
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var revealed: [String: String] = [:]
    @State private var confirmDelete: String?

    var body: some View {
        HubScroll {
            HubSectionHeader(
                title: "环境变量", count: store.envRows.count
            )
            ForEach(store.envRows) { row in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.key)
                            .font(.callout.weight(.medium))
                        Text([
                            row.isSet ? "已设置" : "未设置",
                            revealed[row.key] ?? row.redacted,
                            row.note,
                        ].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if row.isSet && revealed[row.key] == nil {
                        Button("查看") {
                            Task {
                                if let value = await store.revealEnv(
                                    session: session, key: row.key
                                ) {
                                    revealed[row.key] = value
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("删除") { confirmDelete = row.key }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                Divider()
            }
            HubSectionHeader(title: "设置变量")
            TextField("键名", text: $newKey)
                .textFieldStyle(.roundedBorder)
            SecureField("值", text: $newValue)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("保存") {
                    Task {
                        await store.setEnv(
                            session: session, key: newKey,
                            value: newValue
                        )
                        newKey = ""
                        newValue = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newKey.isEmpty)
            }
        }
        .confirmationDialog(
            "删除这个环境变量？",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let key = confirmDelete {
                    Task {
                        await store.deleteEnv(
                            session: session, key: key
                        )
                    }
                }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) { confirmDelete = nil }
        }
    }
}
