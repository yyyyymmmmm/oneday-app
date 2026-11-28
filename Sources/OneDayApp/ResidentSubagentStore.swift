import OneDayCore
import OneDayDesign
import SwiftUI

// MARK: - 常驻分身模型（大厂多体房间协作核心）

/// 单个常驻在线的专家分身：
/// 1. 绑定当前对话（threadID），不随单次任务完成而销毁；
/// 2. 自动接入 `@分身 / @全员` 召唤花名册；
/// 3. 与主助手及其他在线分身共享同一房间上下文，AI 之间互相可见彼此发言；
/// 4. 支持点击卡片一键关闭，或发送 `/close @分身名`、`关闭分身` 等命令关闭。
struct ResidentSubagent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var roleSummary: String
    var model: String?
    var toolsets: [String]
    var threadID: String
    var createdAt: Date
    var lastActiveAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        roleSummary: String,
        model: String? = nil,
        toolsets: [String] = [],
        threadID: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.roleSummary = roleSummary
        self.model = model
        self.toolsets = toolsets
        self.threadID = threadID
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
    }

    /// 转换为与 `ChatMentionPaletteView` 兼容的 `ProfileItem`，让 `@` 浮层无感融合
    func asProfileItem() -> ProfileItem {
        ProfileItem(
            name: name,
            isDefault: false,
            model: model ?? "常驻分身",
            provider: roleSummary.isEmpty ? "房间常驻" : roleSummary,
            gatewayRunning: true
        )
    }
}

// MARK: - 常驻分身持久化仓库

@MainActor
final class ResidentSubagentStore: ObservableObject {
    static let shared = ResidentSubagentStore()
    private static let storageKey = "oneday.residentSubagents.v1"

    @Published private(set) var allAgents: [ResidentSubagent] = []

    private init() {
        load()
    }

    func activeAgents(in threadID: String?) -> [ResidentSubagent] {
        guard let threadID, !threadID.isEmpty else { return [] }
        return allAgents
            .filter { $0.threadID == threadID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    func enlist(
        name: String,
        roleSummary: String,
        model: String? = nil,
        toolsets: [String] = [],
        in threadID: String
    ) -> ResidentSubagent {
        let cleanName = name
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanName.isEmpty ? "专属分身" : cleanName
        let cleanRole = roleSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if let idx = allAgents.firstIndex(where: {
            $0.threadID == threadID && $0.name.caseInsensitiveCompare(finalName) == .orderedSame
        }) {
            allAgents[idx].lastActiveAt = Date()
            if !cleanRole.isEmpty {
                allAgents[idx].roleSummary = cleanRole
            }
            if let model, !model.isEmpty {
                allAgents[idx].model = model
            }
            save()
            return allAgents[idx]
        }

        let agent = ResidentSubagent(
            name: finalName,
            roleSummary: cleanRole.isEmpty ? "常驻协作分身" : cleanRole,
            model: model,
            toolsets: toolsets,
            threadID: threadID
        )
        allAgents.append(agent)
        save()
        return agent
    }

    func dismiss(id: String) {
        allAgents.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func dismiss(named name: String, in threadID: String) -> ResidentSubagent? {
        let target = name
            .replacingOccurrences(of: "@", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        if let idx = allAgents.firstIndex(where: {
            $0.threadID == threadID && (
                $0.name.caseInsensitiveCompare(target) == .orderedSame
                || $0.name.localizedCaseInsensitiveContains(target)
            )
        }) {
            let removed = allAgents.remove(at: idx)
            save()
            return removed
        }
        return nil
    }

    @discardableResult
    func dismissAll(in threadID: String) -> Int {
        let before = allAgents.count
        allAgents.removeAll { $0.threadID == threadID }
        let removedCount = before - allAgents.count
        if removedCount > 0 { save() }
        return removedCount
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ResidentSubagent].self, from: data)
        else { return }
        allAgents = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(allAgents) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - 命令解析器（支持 `/spawn`、`/close` 及中文自然关闭指令）

enum ResidentSubagentCommand: Equatable {
    case spawn(name: String, roleSummary: String)
    case closeNamed(String)
    case closeAll

    static func parse(_ rawText: String, activeAgents: [ResidentSubagent]) -> ResidentSubagentCommand? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. `/spawn 分身名 [职责]`
        if trimmed.lowercased().hasPrefix("/spawn ") {
            let rest = String(trimmed.dropFirst("/spawn ".count)).trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty else { return nil }
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let name = String(parts[0]).replacingOccurrences(of: "@", with: "")
            let role = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "常驻协作分身"
            return .spawn(name: name, roleSummary: role)
        }

        // 2. `/close ...`
        if trimmed.lowercased() == "/close" || trimmed.lowercased() == "/close all" || trimmed.lowercased() == "/close @全员" || trimmed.lowercased() == "/close 全员" {
            return .closeAll
        }
        if trimmed.lowercased().hasPrefix("/close ") {
            let target = String(trimmed.dropFirst("/close ".count))
                .replacingOccurrences(of: "@", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if target.isEmpty || target == "all" || target == "全员" || target == "全部" {
                return .closeAll
            }
            return .closeNamed(target)
        }

        // 3. 自然中文关闭命令（仅在当前房间确有常驻分身且整句是简短关闭指令时拦截）
        guard !activeAgents.isEmpty, trimmed.count <= 24 else { return nil }
        let allClosePhrases = ["关闭所有分身", "关闭全部分身", "结束所有分身", "解散全部分身", "关闭常驻分身"]
        if allClosePhrases.contains(trimmed) {
            return .closeAll
        }
        for prefix in ["关闭分身", "结束分身", "下线分身", "关闭@", "关闭 @", "结束@", "结束 @"] {
            if trimmed.hasPrefix(prefix) {
                let target = String(trimmed.dropFirst(prefix.count))
                    .replacingOccurrences(of: "@", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty {
                    return .closeNamed(target)
                }
            }
        }
        return nil
    }
}

// MARK: - 房间顶部/输入区上方「常驻分身在线条」（大厂群聊协同胶囊）

struct ResidentSubagentBarView: View {
    let agents: [ResidentSubagent]
    let onTapMention: (ResidentSubagent) -> Void
    let onDismiss: (ResidentSubagent) -> Void
    let onAddNew: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Palette.successText)
                        .frame(width: 6, height: 6)
                    Text("常驻分身")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                }
                .padding(.leading, 4)

                ForEach(agents) { agent in
                    HStack(spacing: 5) {
                        Button {
                            Haptics.selection()
                            onTapMention(agent)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.tintLavenderInk)
                                Text("@\(agent.name)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            Haptics.light()
                            withAnimation(.snappy(duration: 0.2)) {
                                onDismiss(agent)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.inkTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭分身 \(agent.name)")
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 6)
                    .padding(.vertical, 5)
                    .background(Palette.surface, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Palette.hairline, lineWidth: 0.75)
                    )
                }

                Button {
                    Haptics.selection()
                    onAddNew()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("开分身")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Palette.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, OneDayMetrics.pageGutter)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - 轻量「开启常驻分身」弹窗

struct SpawnResidentSubagentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var roleSummary = ""
    let onConfirm: (String, String) -> Void

    private let presets: [(name: String, role: String)] = [
        ("编码分身", "负责代码编写、Bug 排查与架构评审"),
        ("研究分身", "负责深度资料检索、竞品调研与方案对比"),
        ("产品分身", "负责需求拆解、交互设计与大厂体验把关"),
        ("运维分身", "负责服务器部署、日志排查与脚本自动化")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("一键常驻预设") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.name) { preset in
                                Button {
                                    name = preset.name
                                    roleSummary = preset.role
                                } label: {
                                    Text(preset.name)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Palette.fillPrimary, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("分身信息") {
                    TextField("分身名称（如：编码分身）", text: $name)
                    TextField("职责说明（其他 AI 也会看到它的分工）", text: $roleSummary, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("开启后该分身会常驻当前对话，随时可敲 @ 派活，主助手与所有分身共享上下文并互相可见；不需要时点卡片 × 或发送「/close @分身名」即可关闭。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("开启常驻分身")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("常驻进群") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !cleanName.isEmpty else { return }
                        onConfirm(cleanName, roleSummary.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
