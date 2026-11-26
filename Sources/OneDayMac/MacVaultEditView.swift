import SwiftUI
import OneDayCore

/// 凭据条目编辑表（棒 2，对位 #71）：新建与整条替
/// 换共用一面。字段行可增删——字段名＋值（密码类
/// 走安全输入）；编辑既有条目时字段名按现条目预
/// 填、值必须重新填写（服务端整条替换、端上从来
/// 读不到旧值）。值只活在本表状态里，保存即弃。
struct MacVaultEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: MacVaultStore
    /// nil＝新建；非 nil＝替换该条目
    let entry: MacVaultEntry?

    @State private var name: String
    @State private var service: String
    @State private var domainsText: String
    @State private var username: String
    @State private var fields: [FieldRow]
    @State private var saving = false

    struct FieldRow: Identifiable {
        let id = UUID()
        var name: String
        var value: String
    }

    init(store: MacVaultStore, entry: MacVaultEntry?) {
        self.store = store
        self.entry = entry
        _name = State(initialValue: entry?.name ?? "")
        _service = State(initialValue: entry?.service ?? "")
        _domainsText = State(
            initialValue: entry?.domains.joined(separator: ", ") ?? ""
        )
        _username = State(initialValue: entry?.username ?? "")
        _fields = State(
            initialValue: (entry?.fieldNames ?? ["password"]).map {
                FieldRow(name: $0, value: "")
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry == nil ? "新建凭据" : "编辑凭据")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                Button(entry == nil ? "保存" : "保存替换") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave || saving)
            }
            .padding(14)
            Divider()
            Form {
                Section("基本") {
                    TextField("名称", text: $name)
                    TextField("服务（如 github）", text: $service)
                    TextField("用户名（可空）", text: $username)
                    TextField(
                        "适用域名（逗号分隔）", text: $domainsText
                    )
                }
                Section("字段值") {
                    ForEach($fields) { $field in
                        HStack(spacing: 8) {
                            TextField("字段名", text: $field.name)
                                .frame(width: 110)
                            if MacVaultFieldCopy.isSecret(field.name) {
                                SecureField("值", text: $field.value)
                            } else {
                                TextField("值", text: $field.value)
                            }
                            Button {
                                fields.removeAll { $0.id == field.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        fields.append(FieldRow(name: "", value: ""))
                    } label: {
                        Label("添加字段", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    if entry != nil {
                        Text("编辑是整条替换：每个字段都要重新填值，没填的字段会被清掉。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("值只在保存时发送给服务端，不保存在本机。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if let note = store.actionNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 560)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !service.trimmingCharacters(in: .whitespaces).isEmpty
            && !fields.isEmpty
            && fields.allSatisfy {
                !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                    && !$0.value.isEmpty
            }
    }

    private func save() async {
        guard canSave, !saving else { return }
        saving = true
        defer { saving = false }
        let domains = domainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var values: [String: String] = [:]
        for field in fields {
            values[field.name.trimmingCharacters(in: .whitespaces)]
                = field.value
        }
        let request = MacVaultWriteRequest(
            name: name.trimmingCharacters(in: .whitespaces),
            service: service.trimmingCharacters(in: .whitespaces),
            domains: domains,
            values: values,
            username: username.trimmingCharacters(in: .whitespaces)
                .isEmpty ? nil : username
        )
        let ok: Bool
        if let entry {
            ok = await store.replaceEntry(
                session: session, id: entry.id, request: request
            )
        } else {
            ok = await store.createEntry(
                session: session, request: request
            )
        }
        if ok { dismiss() }
    }
}
