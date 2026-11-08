import OneDayDesign
import OneDayCore
import SwiftUI

/// 设置：服务器信息、重测连接、断开连接、关于。
/// v2 视觉（docs/DESIGN-V2.md §3.2/§3.5）：弃原生 List 裸样，
/// 与其余四页同一套语言——ScrollView＋SectionLabel＋GroupBox，
/// 信息行走字阶、读数走等宽，危险操作走系统 destructive 角色＋
/// 确认框。功能与逻辑与旧版一致，只换视觉结构。
struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var isRetesting = false
    @State private var retestResult: String?
    @State private var retestFailed = false
    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    serverGroup
                    connectionGroup
                    aboutGroup
                }
                .padding(.horizontal, OneDayMetrics.pageGutter)
                .padding(.top, OneDayMetrics.spacingM)
                .padding(.bottom, OneDayMetrics.spacingXL)
            }
            .background(Palette.pageBG)
            .navigationTitle("设置")
            .confirmationDialog(
                "断开连接？",
                isPresented: $showDisconnectConfirm,
                titleVisibility: .visible
            ) {
                Button("断开连接", role: .destructive) {
                    appState.disconnect()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除这台手机上保存的服务器凭据与登录会话。本地聊天记录保留。")
            }
        }
    }

    // MARK: - 服务器

    private var serverGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务器")
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow(label: "地址", value: appState.config?.baseString ?? "—", mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow(label: "面板账号", value: appState.username ?? "—")
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow(label: "对话模型", value: appState.modelID, mono: true)
            }
            .odGroup()
        }
    }

    // MARK: - 连接

    private var connectionGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("连接")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                Button {
                    Task { await retest() }
                } label: {
                    HStack {
                        Text("重新测试连接")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if isRetesting {
                            ProgressView()
                        }
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isRetesting)
                if let retestResult {
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    resultRow(retestResult)
                }
                GroupDivider(inset: OneDayMetrics.spacingM)
                Button(role: .destructive) {
                    showDisconnectConfirm = true
                } label: {
                    HStack {
                        Text("断开连接")
                            .font(TypeScale.body)
                            .foregroundStyle(Palette.danger)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .odGroup()
        }
    }

    private func resultRow(_ message: String) -> some View {
        Group {
            if retestFailed {
                InlineError(message)
            } else {
                HStack(alignment: .top, spacing: OneDayMetrics.spacingS) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.success)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(TypeScale.subhead)
                        .foregroundStyle(Palette.ink)
                }
            }
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .padding(.vertical, OneDayMetrics.spacingSM)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 关于

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("关于")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                infoRow(label: "OneDay 版本", value: "0.1.2", mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                infoRow(label: "服务端要求", value: "Hermes v0.23.0", mono: true)
                GroupDivider(inset: OneDayMetrics.spacingM)
                Text("OneDay 只与你自己的服务器通信；凭据存本机钥匙串，聊天记录存本机。")
                    .font(TypeScale.footnote)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingSM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .odGroup()
        }
    }

    // MARK: - 行与动作

    private func infoRow(label: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: OneDayMetrics.spacingSM) {
            Text(label)
                .font(TypeScale.body)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: OneDayMetrics.spacingS)
            Text(value)
                .font(mono ? TypeScale.monoCallout : TypeScale.callout)
                .foregroundStyle(Palette.inkSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.horizontal, OneDayMetrics.spacingM)
        .frame(minHeight: OneDayMetrics.rowHeight)
    }

    private func retest() async {
        isRetesting = true
        retestResult = nil
        defer { isRetesting = false }
        do {
            try await appState.retestConnection()
            retestFailed = false
            retestResult = "连接正常：健康检查、登录、API 密钥三步全过。"
        } catch {
            retestFailed = true
            retestResult = (error as? HermesError)?.userMessage ?? "连接失败。"
        }
    }
}
