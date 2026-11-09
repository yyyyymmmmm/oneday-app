import OneDayDesign
import OneDayCore
import SwiftUI

/// 审批桥钥匙（设置·服务器与连接，0.5.0 §31 追加件）：
/// write-gate 桥的单独 Bearer 由用户本人在此粘贴一次，
/// 存 Keychain——写入键与枢纽页 WriteGateClient 的读取
/// 键完全同一（同走 KeychainStore＋CredentialKey.
/// writeGateKey，下方 save/remove/read 三处皆是，代码层
/// 自证读写同键）。页面永不回显钥匙值：已设置只显状态，
/// 钥匙原文只存在于用户正在粘贴的输入框里；钥匙值不进
/// 任何日志、不进 UserDefaults/文件。
struct WriteGateKeySettingsView: View {
    @State private var status: WriteGateKeyStatus = .notSet
    /// 输入框草稿：只装用户新粘贴的内容，保存/移除后即清空
    @State private var draft = ""
    /// 已设置时点「更换」进入输入态
    @State private var isReplacing = false
    @State private var showRemoveConfirm = false

    private var isEntering: Bool { status == .notSet || isReplacing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("审批桥钥匙")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    if isEntering {
                        enterRows
                    } else {
                        setRows
                    }
                }
                .odGroup()

                Text("枢纽页「审核」段经这把钥匙连接审批桥。钥匙只存本机钥匙串，页面不显示原文；更换或移除后，审核段状态按桥的实际连通情况显示。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingM)
        }
        .background(Palette.pageBG)
        .navigationTitle("审批桥钥匙")
        .onAppear { refresh() }
        .confirmationDialog(
            "移除审批桥钥匙？",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) { remove() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移除后审核段回到「通道未接通」。重新粘贴钥匙即可恢复。")
        }
    }

    // MARK: - 未设置 / 更换中：粘贴输入＋保存

    private var enterRows: some View {
        VStack(spacing: 0) {
            SecureField("粘贴审批桥钥匙", text: $draft)
                .font(.system(.callout, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
            GroupDivider(inset: OneDayMetrics.spacingM)
            Button {
                save()
            } label: {
                HStack {
                    Text(isReplacing ? "保存新钥匙" : "保存")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(WriteGateKeyStatus.sanitizedForStorage(draft) == nil)
            if isReplacing {
                GroupDivider(inset: OneDayMetrics.spacingM)
                Button {
                    draft = ""
                    isReplacing = false
                } label: {
                    HStack {
                        Text("取消更换")
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 已设置：只显状态＋更换/移除，永不回显

    private var setRows: some View {
        VStack(spacing: 0) {
            LabeledContent("状态") {
                Text("已设置")
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .frame(minHeight: OneDayMetrics.rowHeight)
            GroupDivider(inset: OneDayMetrics.spacingM)
            Button {
                draft = ""
                isReplacing = true
            } label: {
                HStack {
                    Text("更换")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GroupDivider(inset: OneDayMetrics.spacingM)
            Button(role: .destructive) {
                showRemoveConfirm = true
            } label: {
                HStack {
                    Text("移除")
                        .font(.body)
                    Spacer()
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Keychain 读写（与 WriteGateClient 读取同键）

    /// 状态一律由 Keychain 真实回读派生——保存/移除后都
    /// 重新回读同一键刷新，不靠本地假设（读写同键自证）。
    private func refresh() {
        status = WriteGateKeyStatus.resolve(
            storedValue: KeychainStore.read(account: CredentialKey.writeGateKey)
        )
    }

    private func save() {
        guard let value = WriteGateKeyStatus.sanitizedForStorage(draft) else { return }
        KeychainStore.save(value, account: CredentialKey.writeGateKey)
        draft = ""
        isReplacing = false
        refresh()
    }

    private func remove() {
        KeychainStore.delete(account: CredentialKey.writeGateKey)
        draft = ""
        isReplacing = false
        refresh()
    }
}
