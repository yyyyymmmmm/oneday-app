import LocalAuthentication
import OneDayCore
import OneDayDesign
import SwiftUI

struct VaultRequestsView: View {
    @Environment(AppState.self) private var appState
    @State private var store = VaultStore()
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var isUnlocked = false
    @State private var requests: [VaultRequestMeta] = []
    @State private var loading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if isUnlocked {
                listContent
            } else {
                VStack(spacing: OneDayMetrics.spacingM) {
                    Image(systemName: "faceid")
                        .font(.system(size: 48))
                        .foregroundStyle(Palette.inkMuted)
                    Text("请验证身份以访问待处理请求")
                        .font(.body)
                        .foregroundStyle(Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.settingsBG)
            }
        }
        .navigationTitle("待处理凭据授权请求")
        .navigationBarTitleDisplayMode(.inline)
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
        ScrollView {
            VStack(spacing: OneDayMetrics.spacingM) {
                if loading {
                    ProgressView()
                        .padding(OneDayMetrics.spacingL)
                } else if let error = loadError {
                    VStack(spacing: OneDayMetrics.spacingM) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(Palette.danger)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                            .multilineTextAlignment(.center)

                        if error.contains("404") || error.contains("未启用") {
                            Text("服务端尚未提供凭据请求列表端点 (GET /v1/vault/requests)")
                                .font(.meta)
                                .foregroundStyle(Palette.inkMuted)
                                .multilineTextAlignment(.center)
                                .padding(.top, OneDayMetrics.spacingS)
                        }
                    }
                    .padding(OneDayMetrics.spacingL)
                } else if requests.isEmpty {
                    VStack(spacing: OneDayMetrics.spacingM) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(Palette.success)
                        Text("暂无待处理的凭据请求")
                            .font(.body)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(OneDayMetrics.spacingL)
                } else {
                    ForEach(requests) { request in
                        VaultRequestCard(
                            requestId: request.requestId,
                            service: request.service,
                            domain: request.domain,
                            reason: request.reason,
                            fields: request.fields
                        )
                    }
                }
            }
            .padding(OneDayMetrics.spacingM)
        }
        .background(Palette.settingsBG)
        .refreshable {
            await loadRequests()
        }
        .task {
            await loadRequests()
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
                localizedReason: "访问待处理凭据请求"
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

    private func loadRequests() async {
        guard !loading else { return }

        loading = true
        loadError = nil
        defer { loading = false }

        do {
            requests = try await store.listRequests(appState: appState)
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
}
