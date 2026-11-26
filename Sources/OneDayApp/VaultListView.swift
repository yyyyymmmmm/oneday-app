import LocalAuthentication
import OneDayCore
import OneDayDesign
import SwiftUI

struct VaultListView: View {
    @Environment(AppState.self) private var appState
    @State private var store = VaultStore()
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var isUnlocked = false

    var body: some View {
        Group {
            if isUnlocked {
                listContent
            } else {
                Text("请验证身份以访问凭据库")
                    .font(.body)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .navigationTitle("密码与安全凭证")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink(destination: VaultEditView(entryId: nil, initialEntry: nil)) {
                        Label("新建凭据", systemImage: "plus")
                    }
                    NavigationLink(destination: VaultRequestsView()) {
                        Label("待处理请求", systemImage: "bell")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(!isUnlocked)
            }
        }
        .task {
            await authenticateAndUnlock()
        }
        .alert("验证失败", isPresented: $showBiometricError) {
            Button("关闭", role: .cancel) {}
        } message: {
            Text(biometricErrorMessage)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            if store.loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let error = store.loadError {
                Section {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(Palette.danger)
                }
            } else if store.entries.isEmpty {
                Section {
                    VStack(spacing: OneDayMetrics.spacingM) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 48))
                            .foregroundStyle(Palette.inkMuted)
                        Text("还没有保存任何凭据")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OneDayMetrics.spacingL)
                }
            } else {
                Section {
                    ForEach(store.entries) { entry in
                        NavigationLink(destination: VaultDetailView(entryId: entry.id)) {
                            VaultEntryRow(entry: entry)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .refreshable {
            await store.refresh(appState: appState)
        }
        .task {
            await store.refresh(appState: appState)
        }
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
                localizedReason: "访问密码与安全凭证"
            )
            if passed {
                isUnlocked = true
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
}

struct VaultEntryRow: View {
    let entry: VaultEntryMeta

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
            Text(entry.name)
                .font(.rowTitleL)
                .foregroundStyle(Palette.ink)
            HStack(spacing: OneDayMetrics.spacingS) {
                Text(entry.service)
                    .font(.meta)
                    .foregroundStyle(Palette.inkSecondary)
                if let domain = entry.domains.first {
                    Text("·")
                        .font(.meta)
                        .foregroundStyle(Palette.inkMuted)
                    Text(domain)
                        .font(.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }
}
