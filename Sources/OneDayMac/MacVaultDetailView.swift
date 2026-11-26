import SwiftUI
import OneDayCore
import OneDayDesign

/// 凭据库详情（棒 2，对位 #71/#20）：条目只呈元数
/// 据（值永不回客户端，端上无从显示——与 iOS 详情
/// 同口径）；请求详情带兑现表单（逐字段填值、密码
/// 类走安全输入）与拒绝。写口成败后店内回读对账。
struct MacVaultDetailView: View {
    @Environment(SessionStore.self) private var session
    @Bindable var store: MacVaultStore
    let selection: MacVaultSelection?

    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var fieldValues: [String: String] = [:]

    var body: some View {
        Group {
            switch selection {
            case .entry(let id):
                if let entry = store.entries.first(where: {
                    $0.id == id
                }) {
                    entryDetail(entry)
                } else {
                    placeholder
                }
            case .request(let id):
                if let request = store.requests.first(where: {
                    $0.id == id
                }) {
                    requestDetail(request)
                } else {
                    placeholder
                }
            case nil:
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "选择一条凭据或请求",
            systemImage: "key",
            description: Text("在中间列表里点选，详情在这里打开。")
        )
    }

    // MARK: - 条目详情

    private func entryDetail(_ entry: MacVaultEntry) -> some View {
        Form {
            Section("条目") {
                LabeledContent("名称", value: entry.name)
                LabeledContent("服务", value: entry.service)
                if let username = entry.username, !username.isEmpty {
                    LabeledContent("用户名", value: username)
                }
                LabeledContent(
                    "适用域名",
                    value: entry.domains.isEmpty
                        ? "—" : entry.domains.joined(separator: "、")
                )
                LabeledContent(
                    "字段",
                    value: entry.fieldNames.isEmpty
                        ? "—" : entry.fieldNames.map {
                            MacVaultFieldCopy.displayName($0)
                        }.joined(separator: "、")
                )
                LabeledContent("版本", value: "v\(entry.version)")
                LabeledContent(
                    "更新时间",
                    value: entry.updatedDate.formatted(
                        date: .abbreviated, time: .shortened
                    )
                )
            }
            Section {
                Text("出于安全，凭据的值不在任何端上显示；编辑会整条替换，请备好新值再保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("编辑") { editing = true }
                    Spacer()
                    Button("删除条目", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            if let note = store.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $editing) {
            MacVaultEditView(store: store, entry: entry)
        }
        .confirmationDialog(
            "删除这条凭据？",
            isPresented: $confirmingDelete
        ) {
            Button("删除", role: .destructive) {
                Task { _ = await store.revokeEntry(
                    session: session, id: entry.id
                ) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后智能体将不能再使用这条凭据，此操作不可恢复。")
        }
    }

    // MARK: - 请求详情（兑现/拒绝）

    private func requestDetail(
        _ request: MacVaultRequest
    ) -> some View {
        Form {
            Section("凭据请求") {
                LabeledContent("服务", value: request.service)
                LabeledContent("域名", value: request.domain)
                if !request.reason.isEmpty {
                    LabeledContent("事由", value: request.reason)
                }
                LabeledContent(
                    "需要字段",
                    value: request.fields.map {
                        MacVaultFieldCopy.displayName($0)
                    }.joined(separator: "、")
                )
                LabeledContent(
                    "过期时间",
                    value: request.expiresDate.formatted(
                        date: .abbreviated, time: .shortened
                    )
                )
            }
            if request.isPending {
                Section("提供凭据") {
                    ForEach(request.fields, id: \.self) { field in
                        if MacVaultFieldCopy.isSecret(field) {
                            SecureField(
                                MacVaultFieldCopy.displayName(field),
                                text: binding(for: field)
                            )
                        } else {
                            TextField(
                                MacVaultFieldCopy.displayName(field),
                                text: binding(for: field)
                            )
                        }
                    }
                    HStack {
                        Button("提供") {
                            Task { await fulfill(request) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canFulfill(request))
                        Spacer()
                        Button("拒绝", role: .destructive) {
                            Task {
                                _ = await store.rejectRequest(
                                    session: session,
                                    requestID: request.id
                                )
                            }
                        }
                    }
                    Text("值只在本次提交里发送给服务端，不保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Section {
                    Text("这条请求已\(statusWord(request.status))。")
                        .foregroundStyle(.secondary)
                }
            }
            if let note = store.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .onChange(of: request.id) { _, _ in fieldValues = [:] }
    }

    private func binding(for field: String) -> Binding<String> {
        Binding(
            get: { fieldValues[field] ?? "" },
            set: { fieldValues[field] = $0 }
        )
    }

    /// 与 iOS 卡同一完备判据：字段集齐且逐项非空
    private func canFulfill(_ request: MacVaultRequest) -> Bool {
        Set(fieldValues.keys) == Set(request.fields)
            && fieldValues.values.allSatisfy { !$0.isEmpty }
    }

    private func fulfill(_ request: MacVaultRequest) async {
        guard canFulfill(request) else { return }
        let response = await store.fulfillRequest(
            session: session, requestID: request.id,
            values: fieldValues,
            username: fieldValues["username"]
        )
        if response != nil {
            fieldValues = [:]  // 值用完即弃，不留在界面状态里
        }
    }

    private func statusWord(_ status: String) -> String {
        switch status {
        case "fulfilled": return "处理（已提供）"
        case "rejected": return "处理（已拒绝）"
        case "expired": return "过期"
        default: return "处理"
        }
    }
}
