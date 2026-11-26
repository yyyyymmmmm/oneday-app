import SwiftUI
import OneDayCore
import OneDayDesign

/// 服务器与登录会话页（棒 5 / mac-07，对位 #74/#75/#76）：
/// 严格执行凭据纪律：全包仅用一把主钥（MacKeychain），
/// 面板密码与 API 密钥在界面一律全掩码展示，永不露明文。
struct MacSettingsServerPane: View {
    @Environment(SessionStore.self) private var session

    @State private var authSessions: [AuthSessionSummary] = []
    @State private var sessionsLoading = false
    @State private var sessionsError: String?

    @State private var enrollmentCode: EnrollmentIssue?
    @State private var enrollmentError: String?
    @State private var issuingCode = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        Form {
            if let config = session.config {
                Section("当前服务器") {
                    LabeledContent("主机", value: config.host)
                    LabeledContent("地址", value: config.baseString)
                    LabeledContent("Hermes 版本", value: session.hermesVersion ?? "—")
                    LabeledContent("可用模型", value: "\(session.modelCount) 个")
                    if let summary = session.capabilitySummary {
                        LabeledContent("能力摘要", value: summary)
                    }
                }

                Section {
                    LabeledContent("登录方式", value: "面板密码一步登录（单主钥）")
                    LabeledContent("面板密码", value: "••••••••••••")
                    LabeledContent("API 密钥", value: "••••••••••••")
                    LabeledContent("短时票据", value: shortLivedTokenText)
                } header: {
                    Text("凭据与安全")
                } footer: {
                    Text("凭据仅保存在本机系统钥匙串（site.didichou.oneday），界面全程全掩码显示。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }

                Section("已签发登录会话") {
                    if sessionsLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在加载会话清单…")
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    } else if let sessionsError {
                        Text(sessionsError)
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    } else if authSessions.isEmpty {
                        Text("暂无已签发的设备短时票据会话")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    } else {
                        ForEach(authSessions) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.deviceName.isEmpty ? item.id : item.deviceName)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("版本 \(item.appVersion ?? "—") · 状态 \(item.revoked ? "已撤销" : "有效")")
                                        .font(.caption)
                                        .foregroundStyle(Palette.inkSecondary)
                                }
                                Spacer()
                                if !item.revoked {
                                    Button("撤销", role: .destructive) {
                                        Task { await revoke(sessionID: item.id) }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    Button("刷新会话清单") {
                        Task { await loadAuthSessions() }
                    }
                    .disabled(sessionsLoading)
                }

                Section {
                    if let issued = enrollmentCode {
                        LabeledContent("一次性认领码", value: issued.code)
                        LabeledContent("有效期", value: "\(issued.ttlSeconds) 秒")
                        Button("复制认领码") {
                            Pasteboard.copy(issued.code)
                        }
                    }
                    if let enrollmentError {
                        Text(enrollmentError)
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                    Button(issuingCode ? "正在签发…" : "生成新设备认领码") {
                        Task { await issueCode() }
                    }
                    .disabled(issuingCode)
                } header: {
                    Text("添加设备")
                } footer: {
                    Text("生成一次性认领码供其他设备快速入驻同一台 Hermes 服务器。")
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                }

                Section {
                    Button("断开连接", role: .destructive) {
                        showDisconnectConfirm = true
                    }
                }
            } else {
                Section("当前服务器") {
                    Text("尚未连接服务器。请在主窗口完成连接。")
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await loadAuthSessions()
        }
        .confirmationDialog(
            "确定断开连接？",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("断开连接", role: .destructive) {
                session.disconnect()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除本机钥匙串中保存的服务器凭据与登录会话。")
        }
    }

    private var shortLivedTokenText: String {
        switch session.shortLivedTokensSupported {
        case .some(true): return "服务端支持（当前会话使用长效主钥）"
        case .some(false): return "服务端未启用"
        case .none: return "未读取到能力信息"
        }
    }

    private func loadAuthSessions() async {
        guard let config = session.config, let key = session.apiKey else { return }
        sessionsLoading = true
        sessionsError = nil
        defer { sessionsLoading = false }
        do {
            authSessions = try await session.chatClient.listAuthSessions(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            sessionsError = error.userMessage
        } catch {
            sessionsError = "未读取到设备会话"
        }
    }

    private func revoke(sessionID: String) async {
        guard let config = session.config, let key = session.apiKey else { return }
        do {
            try await session.chatClient.revokeAuthSession(
                config: config, apiKey: key, sessionID: sessionID
            )
            await loadAuthSessions()
        } catch let error as HermesError {
            sessionsError = error.userMessage
        } catch {
            sessionsError = "撤销失败"
        }
    }

    private func issueCode() async {
        guard let config = session.config, let key = session.apiKey else { return }
        issuingCode = true
        enrollmentError = nil
        defer { issuingCode = false }
        do {
            enrollmentCode = try await session.chatClient.issueEnrollmentCode(
                config: config, apiKey: key
            )
        } catch let error as HermesError {
            enrollmentError = error.userMessage
        } catch {
            enrollmentError = "签发认领码失败"
        }
    }
}
