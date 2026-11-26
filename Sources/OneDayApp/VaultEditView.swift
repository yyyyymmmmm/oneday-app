import OneDayCore
import OneDayDesign
import SwiftUI

struct VaultEditView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entryId: String?
    let initialEntry: VaultEntryMeta?

    @State private var store = VaultStore()
    @State private var name = ""
    @State private var service = ""
    @State private var domainsText = ""
    @State private var username = ""
    @State private var selectedFields: Set<VaultFieldType> = []
    @State private var fieldValues: [VaultFieldType: String] = [:]
    @State private var submitting = false
    @State private var submitError: String?
    @State private var validationError: String?

    private var isEditing: Bool { entryId != nil }
    private var isValid: Bool { validationError == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("凭据名称", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()

                    TextField("服务名称", text: $service)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("基本信息")
                }

                Section {
                    TextField("用户名（可选）", text: $username)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .textContentType(.username)
                } header: {
                    Text("账户")
                }

                Section {
                    TextEditor(text: $domainsText)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 80)
                        .onChange(of: domainsText) { _, _ in
                            validateDomains()
                        }

                    if let error = validationError {
                        Text(error)
                            .font(.meta)
                            .foregroundStyle(Palette.danger)
                    }
                } header: {
                    Text("绑定域名")
                } footer: {
                    Text("每行一个域名，如 example.com")
                }

                Section {
                    ForEach(VaultFieldType.allCases, id: \.self) { fieldType in
                        Toggle(fieldType.displayName, isOn: Binding(
                            get: { selectedFields.contains(fieldType) },
                            set: { isSelected in
                                if isSelected {
                                    selectedFields.insert(fieldType)
                                } else {
                                    selectedFields.remove(fieldType)
                                    fieldValues.removeValue(forKey: fieldType)
                                }
                            }
                        ))
                        .tint(Palette.accent)
                    }
                } header: {
                    Text("字段类型")
                }

                if !selectedFields.isEmpty {
                    Section {
                        ForEach(Array(selectedFields).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { fieldType in
                            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                                Text(fieldType.displayName)
                                    .font(.meta)
                                    .foregroundStyle(Palette.inkMuted)

                                if fieldType.isSecret {
                                    SecureField("", text: Binding(
                                        get: { fieldValues[fieldType] ?? "" },
                                        set: { fieldValues[fieldType] = $0 }
                                    ))
                                    .font(.body)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .privacySensitive()
                                } else {
                                    TextField("", text: Binding(
                                        get: { fieldValues[fieldType] ?? "" },
                                        set: { fieldValues[fieldType] = $0 }
                                    ))
                                    .font(.body)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                }
                            }
                            .padding(.vertical, OneDayMetrics.spacingS)
                        }
                    } header: {
                        Text(isEditing ? "字段值（留空 = 本次不提交该字段）" : "字段值")
                    }
                }

                Section {
                    Button {
                        Task {
                            await submitForm()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if submitting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text(isEditing ? "保存" : "创建")
                                    .font(.body)
                                    .foregroundStyle(Palette.accent)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValid || submitting || name.isEmpty || service.isEmpty || domainsText.isEmpty)
                }
            }
            .navigationTitle(isEditing ? "编辑凭据" : "新建凭据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .alert("提交失败", isPresented: Binding(
                get: { submitError != nil },
                set: { if !$0 { submitError = nil } }
            )) {
                Button("关闭", role: .cancel) {}
            } message: {
                if let error = submitError {
                    Text(error)
                }
            }
            .onAppear {
                if let entry = initialEntry {
                    name = entry.name
                    service = entry.service
                    domainsText = entry.domains.joined(separator: "\n")
                    username = entry.username ?? ""
                    for fieldName in entry.fieldNames {
                        if let fieldType = VaultFieldType(rawValue: fieldName) {
                            selectedFields.insert(fieldType)
                        }
                    }
                }
                validateDomains()
            }
        }
    }

    private func validateDomains() {
        let lines = domainsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if lines.isEmpty {
            validationError = "至少需要一个域名"
            return
        }

        for line in lines {
            if line.isEmpty {
                validationError = "域名不能为空"
                return
            }

            if line != line.lowercased() {
                validationError = "域名必须是小写：\(line)"
                return
            }

            if line.contains(" ") {
                validationError = "域名不能包含空格：\(line)"
                return
            }

            if !line.contains(".") {
                validationError = "域名必须包含点号：\(line)"
                return
            }

            let domainRegex = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$/
            if line.firstMatch(of: domainRegex) == nil {
                validationError = "无效的域名格式：\(line)"
                return
            }
        }

        validationError = nil
    }

    private func submitForm() async {
        guard isValid else { return }

        let domains = domainsText.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !domains.isEmpty else {
            submitError = "至少需要一个域名"
            return
        }

        let values = fieldValues.compactMapValues { value in
            value.isEmpty ? nil : value
        }

        guard !values.isEmpty else {
            submitError = "至少需要填写一个字段"
            return
        }

        let usernameValue = username.isEmpty ? nil : username

        submitting = true
        submitError = nil
        defer { submitting = false }

        do {
            if let entryId = entryId {
                _ = try await store.replaceEntry(
                    appState: appState,
                    id: entryId,
                    name: name,
                    service: service,
                    domains: domains,
                    values: values,
                    username: usernameValue
                )
            } else {
                _ = try await store.createEntry(
                    appState: appState,
                    name: name,
                    service: service,
                    domains: domains,
                    values: values,
                    username: usernameValue
                )
            }

            name = ""
            service = ""
            domainsText = ""
            username = ""
            selectedFields.removeAll()
            fieldValues.removeAll()

            dismiss()
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                submitError = L10n.string("凭据库未连接")
            case .failed(let message):
                submitError = message
            }
        } catch {
            submitError = L10n.string("提交失败")
        }
    }
}

enum VaultFieldType: String, CaseIterable, Sendable {
    case username
    case password
    case token
    case apiKey = "api_key"
    case secret
    case otp

    var displayName: String {
        switch self {
        case .username: return "用户名"
        case .password: return "密码"
        case .token: return "令牌"
        case .apiKey: return "API Key"
        case .secret: return "Secret"
        case .otp: return "OTP"
        }
    }

    var isSecret: Bool {
        switch self {
        case .username:
            return false
        case .password, .token, .apiKey, .secret, .otp:
            return true
        }
    }
}
