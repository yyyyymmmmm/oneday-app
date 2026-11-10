import OneDayDesign
import OneDayCore
import SwiftUI

/// 桥钥匙（设置·服务器与连接；0.5.0 单钥版，0.32.1 改
/// 钥匙组，审计 F03/R8）：五桥按 scope 分权——总览只
/// 读/oneday 业务写/writegate 审批写/box 执行/device
/// 设备工具，各自一把、Keychain 分项存。各客户端经
/// BridgeKeyStore 只读自己 scope；分项未配置时【过渡
/// 回退】旧共用钥（writeGateKey，下方旧钥区），服务器
/// 轮换完成后回退失效、下一版删除。
///
/// 本页三区：①钥匙组逐项状态（只认分项本体，不许拿
/// 回退冒充已分权）；②钥匙组导入（多行粘贴 bridge-
/// keys.txt 整段，格式每行 `scope: 钥匙`，解析走 Core
/// BridgeKeyImport）；③旧共用钥（过渡，保留原粘贴/
/// 更换/移除）。页面永不回显任何钥匙值，钥匙原文只存
/// 在于用户正在编辑的输入框；不进日志/文件。
struct WriteGateKeySettingsView: View {
    @Environment(AppState.self) private var appState
    /// 逐项状态：只由分项 Keychain 本体回读派生
    @State private var scopeStatus: [BridgeKeyScope: WriteGateKeyStatus] = [:]
    /// 旧共用钥状态（过渡回退来源）
    @State private var status: WriteGateKeyStatus = .notSet
    /// 旧钥输入草稿：只装用户新粘贴的内容，保存/移除后即清空
    @State private var draft = ""
    /// 已设置时点「更换」进入输入态
    @State private var isReplacing = false
    @State private var showRemoveConfirm = false
    /// 钥匙组导入草稿（整段粘贴，导入后即清空）
    @State private var importDraft = ""
    /// 导入结果如实上报（写入几项、跳过几行）
    @State private var importMessage: String?

    private var isEntering: Bool { status == .notSet || isReplacing }

    private var parsedImport: BridgeKeyImport.Result {
        BridgeKeyImport.parse(importDraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("钥匙组 · 分桥分权")
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    ForEach(
                        Array(BridgeKeyScope.allCases.enumerated()),
                        id: \.element
                    ) { index, scope in
                        if index > 0 {
                            GroupDivider(inset: OneDayMetrics.spacingM)
                        }
                        LabeledContent(scope.displayName) {
                            Text(
                                scopeStatus[scope] == .set
                                    ? "已配置" : "未配置"
                            )
                            .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                    }
                }
                .odGroup()

                SectionLabel("导入钥匙组")
                    .padding(.top, OneDayMetrics.spacingL)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    TextEditor(text: $importDraft)
                        .font(.system(.callout, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 110)
                        .padding(.horizontal, OneDayMetrics.spacingS)
                    GroupDivider(inset: OneDayMetrics.spacingM)
                    Button {
                        importKeys()
                    } label: {
                        HStack {
                            Text("导入")
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if !parsedImport.keys.isEmpty {
                                Text("\(parsedImport.keys.count) 项")
                                    .font(.body)
                                    .foregroundStyle(Palette.inkSecondary)
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                    .disabled(parsedImport.keys.isEmpty)
                }
                .odGroup()
                if let importMessage {
                    Text(importMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingS)
                }
                Text("把钥匙组文件（bridge-keys.txt）的整段内容粘贴到上面，一次配齐五项。每行格式 `scope: 钥匙`，scope 为 overview / oneday / writegate / box / device。页面不保存、不回显钥匙原文。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingM)

                SectionLabel("旧共用钥匙（过渡）")
                    .padding(.top, OneDayMetrics.spacingL)
                    .padding(.bottom, OneDayMetrics.spacingS)
                VStack(spacing: 0) {
                    if isEntering {
                        enterRows
                    } else {
                        setRows
                    }
                }
                .odGroup()

                // 0.7.0：桥鉴权失败如实露脸——总览取数走桥
                // 钥（分项或旧钥回退），未配或被拒时总览/
                // 待审批/通知都取不到数；聊天走 Hermes 本
                // 体通道、不受影响（别让用户对着胶囊猜）
                if appState.overviewBridgeAuthFailed {
                    Text("桥未连接：总览桥鉴权没通过（钥匙未配置或不正确）。聊天不受影响，但总览、待审批与通知暂时取不到数；配好正确钥匙后自动恢复。")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                        .padding(.top, OneDayMetrics.spacingM)
                }

                Text("分项未配置的桥暂时靠旧共用钥匙回退工作；五项配齐后旧钥可以移除。服务器完成钥匙轮换后，旧钥自动失效。所有钥匙只存本机钥匙串，页面不显示原文。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, OneDayMetrics.spacingM)
            }
            .padding(.horizontal, OneDayMetrics.spacingM)
            .padding(.top, OneDayMetrics.spacingM)
        }
        .background(Palette.pageBG)
        .navigationTitle("桥钥匙")
        .onAppear { refresh() }
        .confirmationDialog(
            "移除旧共用钥匙？",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) { remove() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("分项未配置的桥将失去回退来源、回到未接通状态。五项已配齐时移除无影响。")
        }
    }

    // MARK: - 旧钥未设置 / 更换中：粘贴输入＋保存

    private var enterRows: some View {
        VStack(spacing: 0) {
            SecureField("粘贴旧共用钥匙", text: $draft)
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
            .buttonStyle(.odPressable)
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
                .buttonStyle(.odPressable)
            }
        }
    }

    // MARK: - 旧钥已设置：只显状态＋更换/移除，永不回显

    private var setRows: some View {
        VStack(spacing: 0) {
            LabeledContent("状态") {
                Text("已设置（回退来源）")
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
            .buttonStyle(.odPressable)
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
            .buttonStyle(.odPressable)
        }
    }

    // MARK: - Keychain 读写（状态一律回读派生，不靠本地假设）

    private func refresh() {
        for scope in BridgeKeyScope.allCases {
            scopeStatus[scope] = WriteGateKeyStatus.resolve(
                storedValue: BridgeKeyStore.scopedValue(scope)
            )
        }
        status = WriteGateKeyStatus.resolve(
            storedValue: KeychainStore.read(account: CredentialKey.writeGateKey)
        )
    }

    /// 导入：解析结果逐项写入分项键，草稿立即清空，
    /// 结果如实上报（写入项名＋未识别行数，不吞行）
    private func importKeys() {
        let result = parsedImport
        guard !result.keys.isEmpty else { return }
        for (scope, value) in result.keys {
            KeychainStore.save(value, account: CredentialKey.bridgeKey(scope))
        }
        importDraft = ""
        let names = BridgeKeyScope.allCases
            .filter { result.keys[$0] != nil }
            .map(\.displayName)
            .joined(separator: "、")
        var message = "已写入 \(result.keys.count) 项：\(names)。"
        if result.ignoredLineCount > 0 {
            message += "另有 \(result.ignoredLineCount) 行未识别，已跳过。"
        }
        importMessage = message
        refresh()
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
