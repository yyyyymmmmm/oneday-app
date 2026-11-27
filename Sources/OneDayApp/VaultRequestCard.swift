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
            HStack(spacing: OneDayMetrics.spacingSM) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.primary)
                    .frame(width: 36, height: 36)
                    .background(Palette.primaryTint, in: Circle())

                VStack(alignment: .leading, spacing: OneDayMetrics.spacingMicro) {
                    Text("凭据授权请求")
                        .font(.rowTitleL.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(domain.isEmpty ? service : "\(service) · \(domain)")
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            if !reason.isEmpty || isAlwaysAsk {
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                    if !reason.isEmpty {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isAlwaysAsk {
                        HStack(spacing: OneDayMetrics.spacingXS) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(Palette.warningText)
                            Text("已开启每次必问保护")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Palette.warningText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(OneDayMetrics.spacingSM)
                .background(Palette.fillQuaternary, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous))
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
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OneDayMetrics.radiusPreview, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        }
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
        VStack(spacing: OneDayMetrics.spacingSM) {
            ForEach(fields, id: \.self) { field in
                VStack(alignment: .leading, spacing: OneDayMetrics.spacingXS) {
                    Text(fieldDisplayName(field))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)

                    if field == "username" || field == "account" || field == "email" {
                        TextField("输入\(fieldDisplayName(field))", text: Binding(
                            get: { fieldValues[field] ?? "" },
                            set: { fieldValues[field] = $0 }
                        ))
                        .font(.body)
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, 10)
                        .background(Palette.fillQuaternary, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    } else {
                        SecureField("输入\(fieldDisplayName(field))", text: Binding(
                            get: { fieldValues[field] ?? "" },
                            set: { fieldValues[field] = $0 }
                        ))
                        .font(.body.monospaced())
                        .padding(.horizontal, OneDayMetrics.spacingSM)
                        .padding(.vertical, 10)
                        .background(Palette.fillQuaternary, in: RoundedRectangle(cornerRadius: OneDayMetrics.radiusTile, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .privacySensitive()
                    }
                }
            }

            HStack(spacing: OneDayMetrics.spacingSM) {
                Button(role: .destructive) {
                    Haptics.warning()
                    Task {
                        await rejectRequest()
                    }
                } label: {
                    Text("拒绝")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .disabled(submitting)

                Button {
                    Haptics.success()
                    Task {
                        await fulfillRequest()
                    }
                } label: {
                    if submitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    } else {
                        Text("安全提供")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.primary)
                .disabled(submitting || !canFulfill)
            }
            .padding(.top, OneDayMetrics.spacingXS)
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
