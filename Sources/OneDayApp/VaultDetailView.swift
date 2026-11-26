import LocalAuthentication
import OneDayCore
import OneDayDesign
import SwiftUI

struct VaultDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let entryId: String
    @State private var store = VaultStore()
    @State private var entry: VaultEntryMeta?
    @State private var loading = false
    @State private var loadError: String?
    @State private var isUnlocked = false
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var showRevokeConfirm = false
    @State private var revoking = false
    @State private var revokeError: String?

    var body: some View {
        Group {
            if isUnlocked {
                detailContent
            } else {
                VStack(spacing: OneDayMetrics.spacingM) {
                    Image(systemName: "faceid")
                        .font(.system(size: 48))
                        .foregroundStyle(Palette.inkMuted)
                    Text("请验证身份以查看凭据详情")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.settingsBG)
            }
        }
        .navigationTitle("凭据详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await authenticateAndUnlock()
        }
        .alert("验证失败", isPresented: $showBiometricError) {
            Button("关闭", role: .cancel) {}
        } message: {
            Text(biometricErrorMessage)
        }
        .alert("撤销凭据", isPresented: $showRevokeConfirm) {
            Button("取消", role: .cancel) {}
            Button("撤销", role: .destructive) {
                Task {
                    await performRevoke()
                }
            }
        } message: {
            Text("撤销后将无法恢复，确定要继续吗？")
        }
        .alert("撤销失败", isPresented: Binding(
            get: { revokeError != nil },
            set: { if !$0 { revokeError = nil } }
        )) {
            Button("关闭", role: .cancel) {}
        } message: {
            if let error = revokeError {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if loading {
            VStack {
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.settingsBG)
        } else if let error = loadError {
            VStack(spacing: OneDayMetrics.spacingM) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Palette.danger)
                Text(error)
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(OneDayMetrics.spacingL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.settingsBG)
        } else if let entry = entry {
            List {
                Section {
                    detailRow(label: "名称", value: entry.name)
                    detailRow(label: "服务", value: entry.service)

                    if let username = entry.username, !username.isEmpty {
                        detailRow(label: "用户名", value: username)
                    }

                    VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                        Text("绑定域名")
                            .font(.meta)
                            .foregroundStyle(Palette.inkMuted)
                        ForEach(entry.domains, id: \.self) { domain in
                            Text(domain)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .listRowBackground(Palette.surface)

                    detailRow(
                        label: "字段",
                        value: entry.fieldNames.joined(separator: ", ")
                    )

                    detailRow(
                        label: "版本",
                        value: String(entry.version)
                    )

                    detailRow(
                        label: "更新时间",
                        value: formatDate(entry.updatedAtDate)
                    )
                }

                Section {
                    Toggle(
                        "每次必问",
                        isOn: Binding(
                            get: {
                                VaultAlwaysAskPreferences.shared.isAlwaysAsk(entryId: entryId)
                            },
                            set: { newValue in
                                VaultAlwaysAskPreferences.shared.setAlwaysAsk(
                                    entryId: entryId,
                                    enabled: newValue
                                )
                            }
                        )
                    )
                    .tint(Palette.accent)
                    .listRowBackground(Palette.surface)
                } footer: {
                    Text("开启后，每次使用此凭据都需要确认")
                        .font(.meta)
                        .foregroundStyle(Palette.inkMuted)
                }

                Section {
                    Button(role: .destructive) {
                        showRevokeConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if revoking {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Palette.danger)
                            } else {
                                Text("撤销凭据")
                                    .font(.body)
                                    .foregroundStyle(Palette.danger)
                            }
                            Spacer()
                        }
                    }
                    .disabled(revoking)
                    .listRowBackground(Palette.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.settingsBG)
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(label)
                .font(.meta)
                .foregroundStyle(Palette.inkMuted)
            Text(value)
                .font(.body)
                .foregroundStyle(Palette.ink)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
        .listRowBackground(Palette.surface)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func authenticateAndUnlock() async {
        let context = LAContext()
        var evaluateError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &evaluateError
        ) else {
            biometricErrorMessage = BiometricEngine.unavailableText(evaluateError)
            showBiometricError = true
            return
        }

        do {
            let passed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "查看凭据详情"
            )
            if passed {
                isUnlocked = true
                await loadEntry()
            } else {
                biometricErrorMessage = "验证未通过"
                showBiometricError = true
            }
        } catch let error as NSError {
            let code = error.domain == LAErrorDomain
                ? LAError.Code(rawValue: error.code)
                : nil
            switch code {
            case .userCancel, .systemCancel, .appCancel:
                biometricErrorMessage = "验证已取消"
            case .authenticationFailed:
                biometricErrorMessage = "验证失败，请重试"
            default:
                biometricErrorMessage = error.localizedDescription
            }
            showBiometricError = true
        }
    }

    private func loadEntry() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            entry = try await store.getEntry(appState: appState, id: entryId)
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                loadError = L10n.string("凭据库未连接")
            case .failed(let message):
                loadError = message
            }
        } catch {
            loadError = L10n.string("加载失败")
        }
    }

    private func performRevoke() async {
        revoking = true
        revokeError = nil
        defer { revoking = false }

        do {
            try await store.revokeEntry(appState: appState, id: entryId)
            dismiss()
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                revokeError = L10n.string("凭据库未连接")
            case .failed(let message):
                revokeError = message
            }
        } catch {
            revokeError = L10n.string("撤销失败")
        }
    }
}
