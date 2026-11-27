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
    @State private var showCreateEntry = false
    @State private var showRequests = false
    @State private var searchText = ""

    private var filteredEntries: [VaultEntryMeta] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter { entry in
            entry.name.lowercased().contains(q)
                || entry.service.lowercased().contains(q)
                || (entry.username?.lowercased().contains(q) ?? false)
                || entry.domains.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        Group {
            if isUnlocked {
                listContent
            } else {
                ContentUnavailableView {
                    Label("已锁定", systemImage: "lock.shield")
                } description: {
                    Text("请验证身份以访问密码与安全凭证")
                } actions: {
                    Button("验证解锁") {
                        Task { await authenticateAndUnlock() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("密码与安全凭证")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // 0.51.2 修复（真机三报之一）：旧形态把
            // NavigationLink 塞进 Menu——SwiftUI 的
            // Menu 不响应 NavigationLink，点「新建凭
            // 据」只收菜单不跳转，入口等于不存在。改
            // 一级按钮＋@State 驱动：新建走 sheet、
            // 待处理请求走 navigationDestination
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showRequests = true
                } label: {
                    Image(systemName: "bell")
                }
                .disabled(!isUnlocked)
                .accessibilityLabel("待处理请求")
                Button {
                    showCreateEntry = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!isUnlocked)
                .accessibilityLabel("新建凭据")
            }
        }
        .sheet(isPresented: $showCreateEntry) {
            VaultEditView(entryId: nil, initialEntry: nil)
        }
        .navigationDestination(isPresented: $showRequests) {
            VaultRequestsView()
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
            } else if filteredEntries.isEmpty {
                Section {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                Section {
                    ForEach(filteredEntries) { entry in
                        NavigationLink(destination: VaultDetailView(entryId: entry.id)) {
                            VaultEntryRow(entry: entry)
                        }
                    }
                } header: {
                    SettingsSectionHeader("已保存凭据（\(filteredEntries.count)）")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .searchable(text: $searchText, prompt: "搜索名称、服务、用户名或域名")
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

    private var badgeSymbol: String {
        if !entry.domains.isEmpty { return "globe" }
        if entry.fieldNames.contains("api_key") || entry.fieldNames.contains("token") {
            return "key.horizontal"
        }
        return "lock.shield"
    }

    var body: some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Image(systemName: badgeSymbol)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Palette.primary)
                .frame(width: 36, height: 36)
                .background(Palette.primaryTint, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                Text(entry.name)
                    .font(.rowTitleL.weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: OneDayMetrics.spacingXS) {
                    if let username = entry.username, !username.isEmpty {
                        Text(username)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    } else if !entry.service.isEmpty {
                        Text(entry.service)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                    if let domain = entry.domains.first {
                        Text("·")
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                        Text(domain)
                            .font(.footnote)
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: OneDayMetrics.settingsRowHeight)
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
    }
}
