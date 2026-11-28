import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 本地模型管理器（Hermes v0.23.0 `web_routers/local_models.py`）：
/// 展示宿主机 GPU/显存/内存预算、本地推理服务启停、已下载模型激活/卸载/删除，以及官方目录一键下载。
struct LocalModelsManagerView: View {
    @Environment(AppState.self) private var appState

    @State private var status: LocalModelsStatusResponse?
    @State private var hardware: LocalModelsHardwareResponse?
    @State private var catalog: [LocalModelCatalogEntry] = []
    @State private var loading = false
    @State private var busyID: String?
    @State private var errorText: String?
    @State private var feedbackText: String?

    var body: some View {
        List {
            SettingsHeroCard(
                symbol: "cpu.fill",
                tint: Palette.tintLavenderInk,
                title: "本地模型管理",
                subtitle: "监控宿主机显存与内存预算，一键启停本地推理引擎、下载官方推荐量化模型并切换激活。",
                statusText: (status?.serverRunning == true) ? "推理运行中" : "已停止",
                statusTone: (status?.serverRunning == true) ? .healthy : .neutral
            )

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                .listRowBackground(Palette.surface)
            }

            if let feedbackText {
                Section {
                    Label(feedbackText, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.successText)
                }
                .listRowBackground(Palette.surface)
            }

            hardwareAndServerSection
            installedModelsSection
            catalogSection
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(OneDayMetrics.settingsSectionSpacing)
        .scrollContentBackground(.hidden)
        .background(Palette.settingsBG)
        .navigationTitle("本地模型管理")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadAll() }
        .task { await loadAll() }
    }

    private var hardwareAndServerSection: some View {
        Section {
            if let hw = hardware {
                LabeledContent("显存预算", value: hw.vramLabel)
                if let gpu = hw.gpuName, !gpu.isEmpty {
                    LabeledContent("GPU", value: gpu)
                }
                if hw.ramTotalBytes > 0 {
                    LabeledContent(
                        "系统内存",
                        value: "\(formatBytes(hw.ramAvailableBytes)) 可用 / \(formatBytes(hw.ramTotalBytes))"
                    )
                }
            }
            if let status {
                LabeledContent("推理后端", value: status.runtimeBackend ?? "未安装")
                if let active = status.activeModelID, !active.isEmpty {
                    LabeledContent("当前激活", value: active)
                }
                HStack(spacing: 10) {
                    Button(status.serverRunning ? "停止推理服务" : "启动推理服务") {
                        Task { await toggleServer(start: !status.serverRunning) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busyID != nil)

                    if status.activeModelID != nil {
                        Button("释放显存") {
                            Task { await ejectModel(status.activeModelID) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busyID != nil)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        } header: {
            SettingsSectionHeader("宿主机硬件与推理引擎")
        }
        .listRowBackground(Palette.surface)
    }

    private var installedModelsSection: some View {
        Section {
            let models = status?.models ?? []
            if loading && models.isEmpty {
                HStack {
                    ProgressView()
                    Text("正在扫描本地模型…")
                        .font(.rowSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            } else if models.isEmpty {
                Text("宿主机暂未下载本地 GGUF 模型，可从下方推荐目录一键拉取。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(models) { item in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(
                            symbol: item.isActive ? "bolt.circle.fill" : "cube.box.fill",
                            color: item.isActive ? Palette.tintGreenInk : Palette.tintSkyInk
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(item.name)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                if item.isActive {
                                    SettingsStatusPill(text: "运行中", tone: .healthy)
                                }
                            }
                            Text("\(formatBytes(item.sizeBytes))\(item.quant.map { " · \($0)" } ?? "")")
                                .font(.caption.monospaced())
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        Spacer()
                        if !item.isActive {
                            Button(busyID == item.id ? "加载中…" : "启用") {
                                Task { await activateModel(item.id) }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .disabled(busyID != nil)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await deleteModel(item.id) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader("已下载本地模型（左滑删除）")
        }
        .listRowBackground(Palette.surface)
    }

    private var catalogSection: some View {
        Section {
            if catalog.isEmpty {
                Text("暂无可下载目录项。")
                    .font(.rowSubtitle)
                    .foregroundStyle(Palette.inkSecondary)
            } else {
                ForEach(catalog) { entry in
                    HStack(spacing: OneDayMetrics.spacingSM) {
                        SettingsRowIcon(
                            symbol: "arrow.down.circle.fill",
                            color: entry.fits ? Palette.tintGreenInk : Palette.tintOrangeInk
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(entry.name)
                                    .font(.rowTitleL)
                                    .foregroundStyle(Palette.ink)
                                if !entry.fits {
                                    SettingsStatusPill(text: "显存偏紧", tone: .warning)
                                }
                            }
                            if !entry.summary.isEmpty {
                                Text(entry.summary)
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSecondary)
                                    .lineLimit(2)
                            }
                            if let size = entry.sizeLabel, !size.isEmpty {
                                Text(size)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                        Spacer()
                        if entry.installed {
                            SettingsStatusPill(text: "已安装", tone: .healthy)
                        } else {
                            Button(busyID == entry.id ? "拉取中…" : "下载") {
                                Task { await downloadModel(entry.id) }
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .disabled(busyID != nil)
                        }
                    }
                }
            }
        } header: {
            SettingsSectionHeader("推荐模型目录")
        }
        .listRowBackground(Palette.surface)
    }

    private func loadAll() async {
        loading = true
        errorText = nil
        defer { loading = false }

        do {
            status = try await appState.performAdmin { client, config in
                try await client.localModelsStatus(config: config)
            }
            hardware = try? await appState.performAdmin { client, config in
                try await client.localModelsHardware(config: config)
            }
            catalog = (try? await appState.performAdmin { client, config in
                try await client.localModelsCatalog(config: config)
            }) ?? []
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleServer(start: Bool) async {
        busyID = "server"
        defer { busyID = nil }
        do {
            try await appState.performAdmin { client, config in
                try await client.localModelsServerAction(config: config, action: start ? "start" : "stop")
            }
            Haptics.success()
            feedbackText = start ? "本地推理服务已启动" : "本地推理服务已停止"
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func activateModel(_ id: String) async {
        busyID = id
        defer { busyID = nil }
        do {
            try await appState.performAdmin { client, config in
                try await client.activateLocalModel(config: config, modelID: id)
            }
            Haptics.success()
            feedbackText = "已激活本地模型 \(id)"
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func ejectModel(_ id: String?) async {
        busyID = "eject"
        defer { busyID = nil }
        do {
            try await appState.performAdmin { client, config in
                try await client.ejectLocalModel(config: config, modelID: id)
            }
            Haptics.success()
            feedbackText = "已卸载模型并释放显存"
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteModel(_ id: String) async {
        busyID = id
        defer { busyID = nil }
        do {
            try await appState.performAdmin { client, config in
                try await client.deleteLocalModel(config: config, modelID: id)
            }
            Haptics.success()
            feedbackText = "已删除本地模型 \(id)"
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func downloadModel(_ id: String) async {
        busyID = id
        defer { busyID = nil }
        do {
            try await appState.performAdmin { client, config in
                try await client.downloadLocalModel(config: config, modelID: id)
            }
            Haptics.success()
            feedbackText = "已开始在宿主机后台下载 \(id)"
            await loadAll()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
