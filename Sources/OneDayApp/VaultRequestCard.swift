import OneDayCore
import OneDayDesign
import SwiftUI

struct VaultRequestCard: View {
    @Environment(AppState.self) private var appState

    let requestId: String
    let service: String
    let domain: String
    let reason: String
    let fields: [String]

    @State private var store = VaultStore()
    @State private var fieldValues: [String: String] = [:]
    @State private var submitting = false
    @State private var submitError: String?
    @State private var status: RequestCardStatus
    @State private var isAlwaysAsk = false

    /// initialStatus（0.51.2）：结构化块直出时按
    /// 服务端块状态起卡（已提交/已过期不许再摆出
    /// 可填表单）；标记兜底路径不传、恒 pending
    /// 起（与旧形态同）
    init(
        requestId: String,
        service: String,
        domain: String,
        reason: String,
        fields: [String],
        initialStatus: RequestCardStatus = .pending
    ) {
        self.requestId = requestId
        self.service = service
        self.domain = domain
        self.reason = reason
        self.fields = fields
        _status = State(initialValue: initialStatus)
    }

    /// 服务端块/列表状态字面 → 卡内状态（未知字
    /// 面按 pending 起、失效侧由提交回执纠正）
    static func cardStatus(
        forServerStatus status: String
    ) -> RequestCardStatus {
        switch status {
        case "fulfilled", "submitted":
            return .fulfilled(credentialRef: "")
        case "rejected":
            return .rejected
        case "expired":
            return .expired
        case "consumed":
            return .consumed
        default:
            return .pending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OneDayMetrics.spacingM) {
            HStack(spacing: OneDayMetrics.spacingS) {
                ZStack {
                    Circle()
                        .fill(Palette.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "key.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                }

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("凭据请求")
                        .font(.rowTitleL)
                        .foregroundStyle(Palette.ink)

                    Text(service)
                        .font(.meta)
                        .foregroundStyle(Palette.inkSecondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: OneDayMetrics.spacingS) {
                detailRow(label: "域名", value: domain)
                detailRow(label: "原因", value: reason)

                if isAlwaysAsk {
                    HStack(spacing: OneDayMetrics.spacingS) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.meta)
                            .foregroundStyle(Palette.warning)
                        Text("每次必问")
                            .font(.meta)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    .padding(.vertical, OneDayMetrics.spacingMicro)
                }
            }

            switch status {
            case .pending:
                pendingContent
            case .fulfilled(let credentialRef):
                fulfilledContent(credentialRef: credentialRef)
            case .rejected:
                rejectedContent
            case .expired:
                expiredContent
            case .consumed:
                consumedContent
            }
        }
        .padding(OneDayMetrics.spacingM)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusCard, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .alert("操作失败", isPresented: Binding(
            get: { submitError != nil },
            set: { if !$0 { submitError = nil } }
        )) {
            Button("关闭", role: .cancel) {}
        } message: {
            if let error = submitError {
                Text(error)
            }
        }
        .task {
            checkAlwaysAsk()
        }
    }

    @ViewBuilder
    private var pendingContent: some View {
        VStack(spacing: OneDayMetrics.spacingM) {
            ForEach(fields, id: \.self) { field in
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text(fieldDisplayName(field))
                        .font(.meta)
                        .foregroundStyle(Palette.inkMuted)

                    SecureField("", text: Binding(
                        get: { fieldValues[field] ?? "" },
                        set: { fieldValues[field] = $0 }
                    ))
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .privacySensitive()
                }
            }

            HStack(spacing: OneDayMetrics.spacingM) {
                Button {
                    Task {
                        await rejectRequest()
                    }
                } label: {
                    Text("拒绝")
                        .font(.body)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OneDayMetrics.spacingS)
                        .background(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile)
                                .stroke(Palette.danger, lineWidth: 1)
                        )
                }
                .disabled(submitting)

                Button {
                    Task {
                        await fulfillRequest()
                    }
                } label: {
                    if submitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OneDayMetrics.spacingS)
                    } else {
                        Text("提供")
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OneDayMetrics.spacingS)
                    }
                }
                .background(Palette.primary)
                .cornerRadius(OneDayMetrics.radiusTile)
                .disabled(submitting || !canFulfill)
            }
        }
    }

    @ViewBuilder
    private func fulfilledContent(credentialRef: String) -> some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
            Text("已提供 \(fields.joined(separator: ", ")) 凭证")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    @ViewBuilder
    private var rejectedContent: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Palette.danger)
            Text("已拒绝")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    @ViewBuilder
    private var expiredContent: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "clock.fill")
                .foregroundStyle(Palette.warning)
            Text("请求已过期")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    @ViewBuilder
    private var consumedContent: some View {
        HStack(spacing: OneDayMetrics.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.inkMuted)
            Text("请求已处理")
                .font(.body)
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, OneDayMetrics.spacingS)
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
            Text("\(label):")
                .font(.meta)
                .foregroundStyle(Palette.inkMuted)
            Text(value)
                .font(.meta)
                .foregroundStyle(Palette.ink)
        }
    }

    private var canFulfill: Bool {
        Set(fieldValues.keys) == Set(fields) && fieldValues.values.allSatisfy { !$0.isEmpty }
    }

    private func fieldDisplayName(_ field: String) -> String {
        switch field {
        case "username": return "用户名"
        case "password": return "密码"
        case "token": return "令牌"
        case "api_key": return "API Key"
        case "secret": return "Secret"
        case "otp": return "OTP"
        default: return field
        }
    }

    private func checkAlwaysAsk() {
        Task {
            do {
                let entries = store.entries
                if entries.isEmpty {
                    await store.refresh(appState: appState)
                }

                if let matchedEntry = findMatchingEntry(
                    entries: store.entries,
                    service: service,
                    domain: domain
                ) {
                    isAlwaysAsk = VaultAlwaysAskPreferences.shared.isAlwaysAsk(entryId: matchedEntry.id)
                }
            } catch {
            }
        }
    }

    private func findMatchingEntry(entries: [VaultEntryMeta], service: String, domain: String) -> VaultEntryMeta? {
        entries.first { entry in
            entry.service.lowercased() == service.lowercased() &&
            entry.domains.contains { $0.lowercased() == domain.lowercased() }
        }
    }

    private func fulfillRequest() async {
        guard canFulfill else { return }

        submitting = true
        submitError = nil
        defer { submitting = false }

        do {
            let response = try await store.fulfillRequest(
                appState: appState,
                requestId: requestId,
                decision: "fulfill",
                values: fieldValues,
                username: nil
            )

            fieldValues.removeAll()

            if response.status == "fulfilled" {
                status = .fulfilled(credentialRef: response.credentialRef ?? "")
            }
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                submitError = L10n.string("凭据库未连接")
            case .failed(let message):
                if message.contains("410") || message.contains("expired") {
                    status = .expired
                } else if message.contains("409") || message.contains("consumed") {
                    status = .consumed
                } else {
                    submitError = message
                }
            }
        } catch {
            submitError = L10n.string("操作失败")
        }
    }

    private func rejectRequest() async {
        submitting = true
        submitError = nil
        defer { submitting = false }

        do {
            _ = try await store.fulfillRequest(
                appState: appState,
                requestId: requestId,
                decision: "reject",
                values: nil,
                username: nil
            )

            fieldValues.removeAll()
            status = .rejected
        } catch let error as VaultBridgeError {
            switch error {
            case .noKey, .unauthorized:
                submitError = L10n.string("凭据库未连接")
            case .failed(let message):
                if message.contains("410") || message.contains("expired") {
                    status = .expired
                } else if message.contains("409") || message.contains("consumed") {
                    status = .consumed
                } else {
                    submitError = message
                }
            }
        } catch {
            submitError = L10n.string("操作失败")
        }
    }
}

enum RequestCardStatus: Equatable {
    case pending
    case fulfilled(credentialRef: String)
    case rejected
    case expired
    case consumed
}
