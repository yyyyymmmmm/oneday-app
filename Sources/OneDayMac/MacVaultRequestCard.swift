import SwiftUI
import OneDayCore
import OneDayDesign

/// 聊天内嵌凭据请求卡（棒 2，对位 #20）：助手正文
/// 里的 [[vreq:…]] 标记由 Core VaultRequestMarker
/// 摘出、按号向凭据库取元数据渲染（与 iOS 卡同
/// 纪律）——查无此号落回纯文本标记、不摆假卡；待
/// 处理时给逐字段兑现表单与拒绝，处理完原地收成
/// 状态行。值只活在卡内状态里，提交即弃。
struct MacVaultRequestCard: View {
    @Environment(SessionStore.self) private var session
    @Environment(MacVaultStore.self) private var vaultStore
    let requestID: String

    @State private var meta: MacVaultRequest?
    @State private var phase: Phase = .loading
    @State private var fieldValues: [String: String] = [:]
    @State private var submitting = false

    enum Phase: Equatable {
        case loading
        case pending
        case fulfilled(String)
        case rejected
        case expired
        case gone
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取凭据请求…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .gone:
                Text(VaultRequestMarker.markerText(for: requestID))
                    .font(.callout)
                    .textSelection(.enabled)
            case .fulfilled(let ref):
                statusRow(
                    icon: "checkmark.circle.fill", color: .green,
                    text: ref.isEmpty
                        ? "凭据已提供" : "凭据已提供（\(ref)）"
                )
            case .rejected:
                statusRow(
                    icon: "xmark.circle.fill", color: .red,
                    text: "已拒绝提供凭据"
                )
            case .expired:
                statusRow(
                    icon: "clock.fill", color: .orange,
                    text: "请求已过期"
                )
            case .pending:
                if let meta {
                    pendingCard(meta)
                }
            }
        }
        .task { await load() }
    }

    private func statusRow(
        icon: String, color: Color, text: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func pendingCard(_ request: MacVaultRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .foregroundStyle(.orange)
                Text("智能体请求凭据")
                    .font(.headline)
            }
            Text("\(request.service) · \(request.domain)")
                .font(.callout)
                .foregroundStyle(.secondary)
            if !request.reason.isEmpty {
                Text(request.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            ForEach(request.fields, id: \.self) { field in
                if MacVaultFieldCopy.isSecret(field) {
                    SecureField(
                        MacVaultFieldCopy.displayName(field),
                        text: binding(for: field)
                    )
                    .textFieldStyle(.roundedBorder)
                } else {
                    TextField(
                        MacVaultFieldCopy.displayName(field),
                        text: binding(for: field)
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            HStack(spacing: 10) {
                Button("提供") {
                    Task { await fulfill(request) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canFulfill(request) || submitting)
                Button("拒绝", role: .destructive) {
                    Task { await reject(request) }
                }
                .buttonStyle(.borderless)
                .disabled(submitting)
                if submitting {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Text(
                    "过期 \(request.expiresDate.formatted(date: .omitted, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            if let note = vaultStore.actionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(
            Palette.surface, in: RoundedRectangle(cornerRadius: 12)
        )
    }

    // MARK: - 数据与动作

    private func load() async {
        if !vaultStore.loaded {
            await vaultStore.refresh(session: session)
        }
        if let found = vaultStore.request(id: requestID) {
            meta = found
            phase = phaseFor(found.status)
            return
        }
        // 清单里没有：单查状态定性（已处理/已过期/查无此号）
        do {
            let status = try await vaultStore.requestStatus(
                session: session, requestID: requestID
            )
            phase = phaseFor(status.status)
            if phase == .pending {
                await vaultStore.refresh(session: session)
                if let found = vaultStore.request(id: requestID) {
                    meta = found
                    phase = .pending
                } else {
                    phase = .gone
                }
            }
        } catch {
            phase = .gone
        }
    }

    private func phaseFor(_ status: String) -> Phase {
        switch status {
        case "pending": return .pending
        case "fulfilled": return .fulfilled("")
        case "rejected": return .rejected
        case "expired": return .expired
        default: return .gone
        }
    }

    private func binding(for field: String) -> Binding<String> {
        Binding(
            get: { fieldValues[field] ?? "" },
            set: { fieldValues[field] = $0 }
        )
    }

    private func canFulfill(_ request: MacVaultRequest) -> Bool {
        Set(fieldValues.keys) == Set(request.fields)
            && fieldValues.values.allSatisfy { !$0.isEmpty }
    }

    private func fulfill(_ request: MacVaultRequest) async {
        guard canFulfill(request), !submitting else { return }
        submitting = true
        defer { submitting = false }
        let response = await vaultStore.fulfillRequest(
            session: session, requestID: request.id,
            values: fieldValues,
            username: fieldValues["username"]
        )
        if let response {
            fieldValues = [:]
            phase = .fulfilled(response.credentialRef ?? "")
        }
    }

    private func reject(_ request: MacVaultRequest) async {
        guard !submitting else { return }
        submitting = true
        defer { submitting = false }
        if await vaultStore.rejectRequest(
            session: session, requestID: request.id
        ) {
            fieldValues = [:]
            phase = .rejected
        }
    }
}
