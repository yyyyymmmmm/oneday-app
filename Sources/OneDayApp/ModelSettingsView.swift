import OneDayDesign
import OneDayCore
import SwiftUI

/// 模型管理（设置·模型与密钥）：服务端默认模型切换＋
/// 提供商清单。读写走 /api/config 全量：先读全量 JSON、
/// 只改 model/providers 键、整包写回，未知字段原样保留
/// （JSONValue 载体保证不丢字段）。候选与聊天页选择器
/// 同源（0.2.4）：AppState 的上游管线——/api/model/options
/// 优先、用量回落、网关别名硬排除；写回前有候选集校验，
/// 非法值（网关别名等）拦截不写。对话调用网关时填的别名
/// （AppState.modelID）不在此改。
struct ModelSettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var rawConfig: [String: JSONValue] = [:]
    @State private var candidates: [String] = []
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var isLoading = false
    @State private var pendingModel: String?
    @State private var pendingDeleteProvider: String?

    private var currentModel: String? {
        rawConfig["model"]?.stringValue
    }

    /// 候选＝拉取并集去掉当前值（当前值在上方单独成组展示）
    private var switchableModels: [String] {
        candidates.filter { $0 != currentModel }
    }

    private var providers: [(name: String, baseURL: String?)] {
        guard case .object(let dict) = rawConfig["providers"] ?? .null else {
            return []
        }
        return dict.keys.sorted().map { name in
            var baseURL: String?
            if case .object(let fields) = dict[name] ?? .null {
                baseURL = fields["base_url"]?.stringValue
            }
            return (name, baseURL)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                currentGroup
                candidatesGroup
                providersGroup
                if let errorMessage {
                    InlineError(errorMessage)
                        .padding(.top, OneDayMetrics.spacingL)
                }
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.top, OneDayMetrics.spacingM)
                }
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.top, OneDayMetrics.spacingM)
            .padding(.bottom, OneDayMetrics.spacingXL)
        }
        .background(Palette.pageBG)
        // 0.4.0（审计 §3.3 #5）：页名与设置行同口径改
        // 「服务端默认模型」，明示本页语义
        .navigationTitle("服务端默认模型")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(
            "切换默认模型？",
            isPresented: Binding(
                get: { pendingModel != nil },
                set: { if !$0 { pendingModel = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("切换到 \(pendingModel ?? "")") {
                if let model = pendingModel {
                    Task { await setModel(model) }
                }
                pendingModel = nil
            }
            Button("取消", role: .cancel) { pendingModel = nil }
        } message: {
            Text("新的会话将默认使用该模型；已有会话不受影响。")
        }
        .confirmationDialog(
            "删除提供商？",
            isPresented: Binding(
                get: { pendingDeleteProvider != nil },
                set: { if !$0 { pendingDeleteProvider = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let name = pendingDeleteProvider {
                    Task { await deleteProvider(name) }
                }
                pendingDeleteProvider = nil
            }
            Button("取消", role: .cancel) { pendingDeleteProvider = nil }
        } message: {
            Text("将从服务端配置里移除该提供商；使用它的会话可能受影响。")
        }
    }

    private var currentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("服务端默认模型")
                .padding(.bottom, OneDayMetrics.spacingS)
            // 0.4.0（审计 §3.3 #5）：页内语义明示——此值是
            // 服务端新会话的默认，与聊天页胶囊里本机逐请
            // 求选择的模型相互独立
            Text("服务端新会话的默认模型；聊天时实际用的模型由聊天页顶栏胶囊决定。")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    // 0.3.7 卡 8：当前值升摘要卡主读数（等宽大字）
                    Text(currentModel ?? "未配置")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    }
                }
                .padding(.horizontal, OneDayMetrics.spacingM)
                .frame(minHeight: OneDayMetrics.rowHeight)
            }
            .odGroup()
        }
    }

    private var candidatesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("可切换的模型")
                .padding(.top, 28)
                .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if switchableModels.isEmpty {
                    Text("服务端没有返回可切换的模型。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(switchableModels.enumerated()), id: \.element) { index, model in
                    if index > 0 {
                        GroupDivider()
                    }
                    Button {
                        if model != currentModel {
                            pendingModel = model
                        }
                    } label: {
                        HStack(spacing: OneDayMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if let runtime = ModelCatalog.aliasRuntime[model] {
                                    Text("别名 · 将按 \(runtime) 运行")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.inkSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: OneDayMetrics.spacingS)
                            if model == currentModel {
                                Text("当前")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.success)
                            }
                        }
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .frame(minHeight: OneDayMetrics.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.odPressable)
                }
            }
            .odGroup()
        }
    }

    private var providersGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("提供商")
                .padding(.top, 28)
            .padding(.bottom, OneDayMetrics.spacingS)
            VStack(spacing: 0) {
                if providers.isEmpty {
                    Text("暂无提供商条目。")
                        .font(.callout)
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, OneDayMetrics.spacingM)
                        .padding(.vertical, OneDayMetrics.spacingSM)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(providers.enumerated()), id: \.element.name) { index, provider in
                    if index > 0 {
                        GroupDivider()
                    }
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.body)
                                .foregroundStyle(Palette.ink)
                            if let baseURL = provider.baseURL, !baseURL.isEmpty {
                                Text(baseURL)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: OneDayMetrics.spacingS)
                        Button("删除", role: .destructive) {
                            pendingDeleteProvider = provider.name
                        }
                        .font(.callout)
                    }
                    .padding(.horizontal, OneDayMetrics.spacingM)
                    .padding(.vertical, OneDayMetrics.spacingS)
                    .frame(minHeight: OneDayMetrics.rowHeight)
                }
            }
            .odGroup()
        }
    }

    // MARK: - 数据与写入（先读全量、只改目标键、整包写回）

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            rawConfig = try await appState.performAdmin { client, config in
                try await client.rawConfig(config: config)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? HermesError)?.userMessage ?? "配置读取失败。"
        }
        // 0.2.4：候选与聊天页选择器共用 AppState 管线
        // （上游 options 优先、用量回落、网关别名硬排除），
        // 本页不再自拼并集——0.2.2 在这里拼的那份正是把
        // hermes-agent 送进候选的 bug 路径之一
        await appState.refreshModelCatalog()
        candidates = appState.availableModels
    }

    private func writeBack(_ mutate: (inout [String: JSONValue]) -> Void) async throws {
        var updated = rawConfig
        mutate(&updated)
        try await appState.performAdmin { client, config in
            try await client.updateConfig(config: config, newConfig: updated)
        }
        rawConfig = updated
    }

    private func setModel(_ model: String) async {
        // 写入校验（0.2.4）：与选择器同一道闸——不在候选
        // 集内（含网关别名）直接拦截，不发写请求
        guard ModelCatalog.isWritable(model, candidates: candidates) else {
            notice = HermesError.modelNotUpstream(model).userMessage
            return
        }
        do {
            try await writeBack { $0["model"] = .string(model) }
            appState.noteDefaultModel(model)
            notice = "默认模型已切换为 \(model)。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "切换失败，请稍后再试。"
        }
    }

    private func deleteProvider(_ name: String) async {
        do {
            try await writeBack { config in
                if case .object(var providers) = config["providers"] ?? .null {
                    providers[name] = nil
                    config["providers"] = .object(providers)
                }
            }
            notice = "提供商 \(name) 已删除。"
        } catch {
            notice = (error as? HermesError)?.userMessage ?? "删除失败，请稍后再试。"
        }
    }
}
