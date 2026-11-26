import SwiftUI
import AppKit
import OneDayCore
import OneDayDesign

/// 设置侧边栏一级分类（棒 5 / mac-07，对标 macOS 系统设置双栏架构）：
/// 左侧 196pt 原生侧边栏＋右侧 Grouped Form，全覆盖 iOS 设置 #65–#89
/// ＋连接自检/体检/日志/聊天诊断＋M2 速记窗热键改键录制器。
enum MacSettingsCategory: String, CaseIterable, Identifiable {
    case general
    case appearance
    case notifications
    case server
    case diagnostics
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观"
        case .notifications: return "通知与互动"
        case .server: return "服务器与会话"
        case .diagnostics: return "诊断与日志"
        case .about: return "帮助与关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .notifications: return "bell.badge"
        case .server: return "server.rack"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .blue
        case .notifications: return .red
        case .server: return .indigo
        case .diagnostics: return .green
        case .about: return .teal
        }
    }
}

struct MacSettingsView: View {
    @Environment(SessionStore.self) private var session
    var quickEntry: MacQuickEntryController?

    @State private var selected: MacSettingsCategory? = .general
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResultsSection
                } else {
                    ForEach(MacSettingsCategory.allCases) { category in
                        Label {
                            Text(category.title)
                                .font(.system(size: 13))
                        } icon: {
                            Image(systemName: category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(
                                    category.tint.gradient,
                                    in: RoundedRectangle(
                                        cornerRadius: 5, style: .continuous
                                    )
                                )
                        }
                        .tag(category)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "搜索设置")
            .navigationSplitViewColumnWidth(min: 184, ideal: 196, max: 230)
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, idealWidth: 780, minHeight: 540, idealHeight: 580)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selected ?? .general {
        case .general:
            MacSettingsGeneralPane(quickEntry: quickEntry)
        case .appearance:
            MacSettingsAppearancePane()
        case .notifications:
            MacSettingsNotificationsPane()
        case .server:
            MacSettingsServerPane()
        case .diagnostics:
            MacSettingsDiagnosticsPane()
        case .about:
            MacSettingsAboutPane()
        }
    }

    /// 复用 Core SettingsCatalog.search 单源搜索，命中直达对应设置分类
    private var searchResultsSection: some View {
        let hits = SettingsCatalog.search(searchText)
        return Section("搜索结果") {
            if hits.isEmpty {
                Text("未找到匹配设置项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(hits) { entry in
                    Button {
                        selected = Self.category(for: entry.destination)
                        searchText = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.ink)
                            Text(Self.category(for: entry.destination).title)
                                .font(.caption2)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static func category(
        for destination: SettingsDestination
    ) -> MacSettingsCategory {
        switch destination {
        case .appearance: return .appearance
        case .language, .identity: return .general
        case .notifications, .interaction, .voice: return .notifications
        case .serverDetail, .authSessions, .addDevice, .disconnect:
            return .server
        case .connectionSelfCheck, .healthCheck, .logs, .chatDiagnostics,
             .crashReports, .advancedDiagnostics, .gateway, .envVars,
             .mainSession, .pairingManagement:
            return .diagnostics
        case .help, .about, .privacy, .terms:
            return .about
        default:
            return .general
        }
    }
}

// MARK: - 通用页（#65 身份 / #66 语言 / M2 速记窗热键改键录制器）

struct MacSettingsGeneralPane: View {
    @Environment(SessionStore.self) private var session
    var quickEntry: MacQuickEntryController?

    @AppStorage(LanguageStorageKeys.appLanguage)
    private var appLanguageRaw = AppLanguagePreference.system.rawValue

    private var languageBinding: Binding<AppLanguagePreference> {
        Binding(
            get: { AppLanguagePreference(rawValue: appLanguageRaw) ?? .system },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("当前身份") {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Palette.primaryTint)
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Palette.primary)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(session.agentDisplayName ?? AgentName.fallback)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Circle()
                                .fill(session.isConnected ? Palette.success : Palette.inkMuted)
                                .frame(width: 8, height: 8)
                        }
                        Text(
                            session.config?.host ?? "未连接服务器"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                LabeledContent(
                    "当前档案",
                    value: session.activeProfileName ?? "—"
                )
            }

            Section {
                Picker("界面语言", selection: languageBinding) {
                    ForEach(AppLanguagePreference.allCases) { pref in
                        Text(L10n.string(pref.displayKey)).tag(pref)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("语言")
            } footer: {
                Text("系统弹窗与文件选择器等由 macOS 托管的界面仍跟随系统语言。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }

            Section {
                MacHotKeyRecorderRow(controller: quickEntry ?? MacQuickEntryController.shared)
            } header: {
                Text("速记窗全局热键")
            } footer: {
                Text("在任意应用中按下此快捷键可立即呼出置顶速记窗；需包含 ⌘ / ⌥ / ⌃ 至少一个修饰键。")
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// M2 热键改键录制器（棒 5 补齐棒 3 顺延项）：
/// 使用原生 NSEvent.addLocalMonitorForEvents 捕获组合键，
/// 录制完成后立即热重绑 Carbon RegisterEventHotKey。
struct MacHotKeyRecorderRow: View {
    var controller: MacQuickEntryController?
    @State private var currentBinding: MacHotKeyBinding = MacHotKeyBinding.load()
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("呼出速记窗")
                Spacer()
                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecording ? "请按下组合键…（Esc 取消）" : currentBinding.displayString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            isRecording ? Palette.primaryTint : Palette.fillQuaternary,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isRecording ? Palette.primary : Palette.separator.opacity(0.6),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)

                if currentBinding != .default {
                    Button("恢复默认") {
                        stopRecording()
                        controller?.resetHotKey()
                        if controller == nil { MacHotKeyBinding.reset() }
                        currentBinding = .default
                        hint = "已恢复默认 ⌥Space"
                    }
                    .controlSize(.small)
                }
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        hint = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let carbonMods = MacHotKeyBinding.carbonModifiers(from: flags)
            guard carbonMods != 0 else {
                hint = "请同时按住 ⌘、⌥ 或 ⌃ 等修饰键"
                return nil
            }
            let next = MacHotKeyBinding(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: carbonMods
            )
            currentBinding = next
            if let controller {
                controller.updateHotKey(next)
            } else {
                next.save()
            }
            hint = "已更新为 \(next.displayString)"
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
