import Foundation
import OneDayCore
import OneDayDesign
import SwiftUI

/// 已保存的 Hermes 网关实例配置（支持多网关实例管理与一键热切换）。
struct SavedGatewayInstance: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var serverAddress: String
    var apiKey: String
    var note: String = ""
    var lastConnectedAt: Date?
}

/// 多网关实例本地仓（自动同步记录当前已连接网关，支持新增、编辑、删除与一键切换）。
@MainActor
@Observable
final class MultiGatewayStore {
    static let shared = MultiGatewayStore()

    private static let storageKey = "oneday.multi.gateway.instances.v1"

    var instances: [SavedGatewayInstance] = []

    private init() {
        load()
    }

    func ensureCurrentRecorded(config: ServerConfig?, apiKey: String?) {
        guard let config else { return }
        let normalized = config.baseString
        if let idx = instances.firstIndex(where: { $0.serverAddress == normalized }) {
            instances[idx].lastConnectedAt = Date()
            if let apiKey, !apiKey.isEmpty {
                instances[idx].apiKey = apiKey
            }
        } else {
            instances.insert(
                SavedGatewayInstance(
                    name: config.host,
                    serverAddress: normalized,
                    apiKey: apiKey ?? "",
                    note: "当前主网关",
                    lastConnectedAt: Date()
                ),
                at: 0
            )
        }
        save()
    }

    func upsert(_ instance: SavedGatewayInstance) {
        if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[idx] = instance
        } else {
            instances.append(instance)
        }
        save()
    }

    func delete(id: UUID) {
        instances.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SavedGatewayInstance].self, from: data)
        else { return }
        instances = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(instances) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// 嵌入 `ServerDetailView` 的多网关实例切换分组。
struct MultiGatewaySection: View {
    @Environment(AppState.self) private var appState
    let onSwitched: (String, String) -> Void

    @State private var store = MultiGatewayStore.shared
    @State private var switchingID: UUID?
    @State private var switchError: String?
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newAddress = ""
    @State private var newAPIKey = ""
    @State private var newNote = ""

    var body: some View {
        Section {
            ForEach(store.instances) { item in
                let isActive = item.serverAddress == appState.config?.baseString
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(
                        symbol: isActive ? "checkmark.circle.fill" : "server.rack",
                        color: isActive ? Palette.tintGreenInk : Palette.tintSkyInk
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.name)
                                .font(.rowTitleL)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if isActive {
                                SettingsStatusPill(text: "当前", tone: .healthy)
                            }
                        }
                        Text(item.serverAddress)
                            .font(.caption.monospaced())
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !item.note.isEmpty {
                            Text(item.note)
                                .font(.caption2)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: OneDayMetrics.spacingS)
                    if switchingID == item.id {
                        ProgressView()
                            .controlSize(.small)
                    } else if !isActive {
                        Button("切换") {
                            Task { await switchTo(item) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isActive {
                        Button("删除", role: .destructive) {
                            store.delete(id: item.id)
                            Haptics.selection()
                        }
                    }
                }
            }

            Button {
                newName = ""
                newAddress = ""
                newAPIKey = ""
                newNote = ""
                showAddSheet = true
            } label: {
                HStack(spacing: OneDayMetrics.spacingSM) {
                    SettingsRowIcon(symbol: "plus.circle.fill", color: Palette.primary)
                    Text("添加网关实例")
                        .font(.rowTitleL.weight(.medium))
                        .foregroundStyle(Palette.primary)
                }
                .frame(minHeight: OneDayMetrics.settingsRowHeight)
            }
        } header: {
            SettingsSectionHeader("多网关实例切换")
        } footer: {
            if let switchError {
                Text(switchError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            } else {
                Text("支持在自宅 Mac、云端 VPS、团队测试服等多台 Hermes 网关之间一键热切换。")
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .listRowBackground(Palette.surface)
        .listRowInsets(OneDayMetrics.settingsRowInsets)
        .onAppear {
            store.ensureCurrentRecorded(config: appState.config, apiKey: appState.apiKey)
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                Form {
                    Section("网关信息") {
                        TextField("名称（如：家庭 Mac / 东京 VPS）", text: $newName)
                        TextField("网关地址（https://...）", text: $newAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Bearer 密钥", text: $newAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("备注（可选）", text: $newNote)
                    }
                }
                .navigationTitle("添加 Hermes 网关")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showAddSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            let trimmedAddress = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmedAddress.isEmpty else { return }
                            let normalized = ServerConfig(rawInput: trimmedAddress)?.baseString ?? trimmedAddress
                            store.upsert(
                                SavedGatewayInstance(
                                    name: trimmedName.isEmpty ? (ServerConfig(rawInput: trimmedAddress)?.host ?? normalized) : trimmedName,
                                    serverAddress: normalized,
                                    apiKey: newAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                                    note: newNote.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                            )
                            Haptics.success()
                            showAddSheet = false
                        }
                        .disabled(newAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func switchTo(_ item: SavedGatewayInstance) async {
        switchError = nil
        guard let config = ServerConfig(rawInput: item.serverAddress) else {
            switchError = "网关地址无效：\(item.serverAddress)"
            Haptics.error()
            return
        }
        switchingID = item.id
        defer { switchingID = nil }
        do {
            try await appState.connectDirect(config: config, apiKey: item.apiKey)
            store.ensureCurrentRecorded(config: config, apiKey: item.apiKey)
            onSwitched(config.baseString, item.apiKey)
            Haptics.success()
        } catch {
            switchError = (error as? HermesError)?.userMessage ?? "切换失败：\(error.localizedDescription)"
            Haptics.error()
        }
    }
}
